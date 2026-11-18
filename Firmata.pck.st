'From Cuis7.8 [latest update: #7977] on 14 September 2026 at 12:45:22 pm'!
'Description Please enter a description for this package'!
!provides: 'Firmata' 1 4!
!requires: 'SerialPort' 1 2 nil!
SystemOrganization addCategory: #Firmata!


!classDefinition: #Firmata category: #Firmata!
Object subclass: #Firmata
	instanceVariableNames: 'port analogInputData digitalInputData digitalOutputData parsingSysex storedInputData sysexBytesRead waitForData executeMultiByteCommand multiByteChannel majorVersion minorVersion steppingProcess'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Firmata'!
!classDefinition: 'Firmata class' category: #Firmata!
Firmata class
	instanceVariableNames: ''!

!classDefinition: #FirmataConstants category: #Firmata!
Object subclass: #FirmataConstants
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Firmata'!
!classDefinition: 'FirmataConstants class' category: #Firmata!
FirmataConstants class
	instanceVariableNames: ''!

!Firmata commentStamp: 'GuillermoPolito 3/29/2017 15:53' prior: 0!
I am an implementation of the Firmata protocol for talking to an Arduino board. 
For more information check: http://www.firmata.org/

This implementation is mostly based on FirmataVB by Andrew Craigie.
http://www.acraigie.com/programming/firmatavb/default.html

| firmata |

firmata := Firmata new
	connectOnPort: '/dev/ttyACM0'
	baudRate: 57600.
	
firmata isConnected.
firmata digitalPin: 13 mode: FirmataConstants pinModeOutput.

firmata digitalWrite: 13 value: 1.
(Delay forSeconds: 1) wait.
firmata digitalWrite: 13 value: 0.
(Delay forSeconds: 1) wait.
firmata digitalWrite: 13 value: 1.
(Delay forSeconds: 1) wait.
firmata digitalWrite: 13 value: 0.
(Delay forSeconds: 1) wait.
firmata digitalWrite: 13 value: 1.

firmata disconnect.
!

!FirmataConstants commentStamp: 'Richo 9/15/2009 12:00' prior: 0!
See class side. I collect a bunch of constants for the Firmata protocol.!

!Firmata methodsFor: 'printing' stamp: 'GitHub 1/Aug/2017 12:33:41'!
printOn: aStream
super printOn: aStream.
aStream nextPutAll: '(',self hash asString,')'! !

!Firmata methodsFor: 'accessing' stamp: 'GitHub 1/Aug/2017 12:33:41'!
majorVersion
^majorVersion! !

!Firmata methodsFor: 'accessing' stamp: 'GitHub 1/Aug/2017 12:33:41'!
majorVersion: version1 minorVersion: version2
majorVersion := version1.
minorVersion := version2! !

!Firmata methodsFor: 'accessing' stamp: 'GitHub 1/Aug/2017 12:33:41'!
minorVersion
^minorVersion! !

!Firmata methodsFor: 'accessing' stamp: 'GitHub 1/Aug/2017 12:33:41'!
nameSymbol
	^ #firmata! !

!Firmata methodsFor: 'accessing' stamp: 'GitHub 1/Aug/2017 12:33:41'!
port
	self controlConnection.
	^port! !

!Firmata methodsFor: 'accessing' stamp: 'GitHub 1/Aug/2017 12:33:41'!
version
"self queryVersion."
^(majorVersion asString , '.', minorVersion asString) asNumber! !

!Firmata methodsFor: 'stepping' stamp: 'sf 14/Sep/2026 10:15:37'!
startSteppingProcess
	"Poll the serial/network port from a background process that stops by itself
	once the connection is closed. See #step for connection errors.
	In Cuis, #forkNamed: does not answer the new Process, so build it
	explicitly to keep a handle for #stopSteppingProcess."
	steppingProcess notNil
		ifTrue: [^ self].
	steppingProcess := [
		[[ self isConnected ] whileTrue: [
			self step.
			(Delay forMilliseconds: self stepTime) wait]]
			ensure: [ steppingProcess := nil ]]
			newProcess.
	steppingProcess priority: Processor activePriority.
	steppingProcess name: self asString.
	steppingProcess resume ! !

!Firmata methodsFor: 'stepping' stamp: 'sf 12/Sep/2026 11:18:53'!
step
	"A serial error makes the connection unusable. Drop the port so that
	#startSteppingProcess sees the connection as closed and stops."
	[ self processInput ]
		on: Error
		do: [ :error |
			port := nil.
			Transcript show: 'Firmata connection error: ' , error messageText ] ! !

!Firmata methodsFor: 'stepping' stamp: 'GitHub 1/Aug/2017 12:33:41'!
stepTime
	^ 1! !

!Firmata methodsFor: 'stepping' stamp: 'GitHub 1/Aug/2017 12:33:41'!
stopSteppingProcess
	steppingProcess isNil
		ifTrue: [^ self].
	steppingProcess terminate. 
	steppingProcess := nil! !

!Firmata methodsFor: 'receiving' stamp: 'GitHub 1/Aug/2017 12:33:41'!
parseCommandHeader: inputByte 
"I check the inputByte for a command header and then I set the variables accordingly to process the data in the following step"
	| command |
	inputByte < 240
		ifTrue: [command := inputByte bitAnd: 240.
			multiByteChannel := inputByte bitAnd: 15.]
		ifFalse: [command := inputByte].
	command caseOf: {
		[FirmataConstants analogMessage] -> 
			[waitForData := 2.
			executeMultiByteCommand := command].
		[FirmataConstants digitalMessage] -> 
			[waitForData := 2.
			executeMultiByteCommand := command].
		[FirmataConstants setPinMode] -> 
			[waitForData := 2.
			executeMultiByteCommand := command].
		[FirmataConstants reportDigital] -> 
			[waitForData := 1.
			executeMultiByteCommand := command].
		[FirmataConstants startSysex] -> 
			[parsingSysex := true.
			sysexBytesRead := 0].
		[FirmataConstants reportVersion] -> 
			[waitForData := 2.
			executeMultiByteCommand := command]}
		 otherwise: []! !

!Firmata methodsFor: 'receiving' stamp: 'GitHub 1/Aug/2017 12:33:41'!
parseData: inputByte 
"I check inputByte for data according to the command header I found in the previous step, then I use the data to set the corresponding variables"

	waitForData := waitForData - 1.
	storedInputData at: waitForData + 1 put: inputByte.

	(waitForData = 0
			and: [executeMultiByteCommand ~= 0])
		ifTrue: [executeMultiByteCommand caseOf: {
				[FirmataConstants analogMessage] -> [self setAnalogInput: multiByteChannel value: (storedInputData first bitShift: 7)
						+ storedInputData second].
				[FirmataConstants digitalMessage] -> [
						self setDigitalInputs: multiByteChannel data: (storedInputData first bitShift: 7)
						+ storedInputData second].
				[FirmataConstants reportVersion] -> [self majorVersion: storedInputData second minorVersion: storedInputData first]}
				 otherwise: [].
			executeMultiByteCommand := 0]! !

!Firmata methodsFor: 'receiving' stamp: 'sf 12/Sep/2026 11:15:42'!
parseSysex: inputByte 
	inputByte = FirmataConstants endSysex
		ifTrue: [parsingSysex := false.
			sysexBytesRead := 0]
		ifFalse: [sysexBytesRead < storedInputData size
				ifTrue: [storedInputData at: sysexBytesRead + 1 put: inputByte].
			sysexBytesRead := sysexBytesRead + 1]! !

!Firmata methodsFor: 'receiving' stamp: 'GitHub 1/Aug/2017 12:33:41'!
processInput
	| data |
	data := port readByteArray.

	data
		do: [:inputByte | 

parsingSysex
				ifTrue: [self parseSysex: inputByte]
				ifFalse: [(waitForData > 0
							and: [inputByte < 128])
						ifTrue: [self parseData: inputByte]
						ifFalse: [self parseCommandHeader: inputByte]]]! !

!Firmata methodsFor: 'testing' stamp: 'sf 12/Sep/2026 01:06:11'!
isFirmataInstalled
"I check if Firmata responds well to queryVersion. I try for 5 seconds"
| t timeout |
t := Time millisecondClockValue.
timeout := 5000.
[self queryVersion. 500 milliSeconds asDelay wait.
self version > 0 or: [(Time millisecondClockValue - t) > timeout]] whileFalse.
^self version > 0! !

!Firmata methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
valueForInputMode
^FirmataConstants pinModeInput! !

!Firmata methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
valueForOutputMode
^FirmataConstants pinModeOutput ! !

!Firmata methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
valueForPwmMode
^FirmataConstants pinModePwm! !

!Firmata methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
valueForServoMode
^FirmataConstants pinModeServo ! !

!Firmata methodsFor: 'servos' stamp: 'GitHub 1/Aug/2017 12:33:41'!
attachServoToPin: pinNumber 
	self
		servoConfig: pinNumber
		minPulse: 544
		maxPulse: 2400
		angle: 0! !

!Firmata methodsFor: 'servos' stamp: 'GitHub 1/Aug/2017 12:33:41'!
detachServoFromPin: pinNumber 
	self pin: pinNumber mode: FirmataConstants pinModeOutput ! !

!Firmata methodsFor: 'servos' stamp: 'GitHub 1/Aug/2017 12:33:41'!
servoConfig: pin minPulse: minPulse maxPulse: maxPulse angle: angle
	"Default values: 
	minPulse 544 (LSB 32 MSB 4)
	maxPulse 2400 (LSB 96 MSB 18
	"
	| b |
	b := ByteArray new: 10.
	b at: 1 put: FirmataConstants startSysex;
		 at: 2 put: FirmataConstants servoConfig;
		 at: 3 put: pin;
		 at: 4 put:  (minPulse rounded bitAnd: 127);
		 at: 5 put: ((minPulse rounded bitShift: -7)
				bitAnd: 127);
		 at: 6 put: (maxPulse rounded bitAnd: 127);
		 at: 7 put: ((maxPulse rounded bitShift: -7)
				bitAnd: 127);
		 at: 8 put: (angle rounded bitAnd: 127);
		 at: 9 put: ((angle rounded bitShift: -7)
				bitAnd: 127);
		 at: 10 put: FirmataConstants endSysex.
	self port nextPutAll: b! !

!Firmata methodsFor: 'servos' stamp: 'GitHub 1/Aug/2017 12:33:41'!
servoOnPin: pinNumber angle: degrees
self analogWrite: pinNumber value: degrees! !

!Firmata methodsFor: 'initialize-release' stamp: 'GitHub 1/Aug/2017 12:33:41'!
initialize
self initializeVariables! !

!Firmata methodsFor: 'initialize-release' stamp: 'sf 12/Sep/2026 11:12:19'!
initializeVariables
	digitalOutputData := Array new: 16 withAll: 0.
	digitalInputData := Array new: 16 withAll: 0.
	analogInputData := Array new: 16 withAll: 0.
	storedInputData := Array new: 4096 withAll: 0.
	parsingSysex := false.
	sysexBytesRead := waitForData := executeMultiByteCommand := multiByteChannel := majorVersion := minorVersion := 0! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
activateDigitalPort: n
			self digitalPortReport: n onOff: 1
! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
analogWrite: pin value: value 
	"Sends a PWM value to a digital pin. 0 - 255"
	| analogWriteBuffer |
	analogWriteBuffer := ByteArray new: 3 withAll: 0.
	analogWriteBuffer
		at: 1
		put: (FirmataConstants analogMessage
				bitOr: (pin bitAnd: 15));
		
		at: 2
		put: (value rounded bitAnd: 127);
		
		at: 3
		put: ((value rounded bitShift: -7)
				bitAnd: 127).
self port  nextPutAll: analogWriteBuffer! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
deactivateDigitalPort: n
			self digitalPortReport: n onOff: 0
! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
digitalPin: pinNumber mode: mode
"Digital ports should always be active"
pinNumber <= 7
	ifTrue: [self activateDigitalPort: 0]
	ifFalse: [self activateDigitalPort: 1].
self  pin: pinNumber mode: mode! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
digitalPortReport: port1 onOff: onOff
"Sends a message to toggle reporting for a whole digital port"
	self port 
		nextPutAll: (ByteArray
				with: (FirmataConstants reportDigital bitOr: port1 )
				with: onOff)! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
digitalRead: pinNumber 
	"Retuns On/Off data for an individual Digital Pin"
	^ ((digitalInputData at: (pinNumber bitShift: -3)
			+ 1)
		bitShift: (pinNumber bitAnd: 7) * -1)
		bitAnd: 1! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
digitalWrite: pin value: value 
	"Sends an On or Off message to an individual Digital Pin"
	| portNumber adjustment digitalWriteBuffer |
	portNumber := (pin bitShift: -3)
				bitAnd: 15.
	adjustment := 1
				bitShift: (pin bitAnd: 7).
	digitalWriteBuffer := ByteArray new: 3 withAll: 0.
	value = 0
		ifTrue: [digitalOutputData
				at: portNumber + 1
				put: ((digitalOutputData at: portNumber + 1)
						bitAnd: adjustment bitInvert)]
		ifFalse: [digitalOutputData
				at: portNumber + 1
				put: ((digitalOutputData at: portNumber + 1)
						bitOr: adjustment)].
	digitalWriteBuffer
		at: 1
		put: (FirmataConstants digitalMessage bitOr: portNumber);
		at: 2
		put: ((digitalOutputData at: portNumber + 1)
				bitAnd: 127);
		at: 3
		put: ((digitalOutputData at: portNumber + 1)
				bitShift: -7).
	self port nextPutAll: digitalWriteBuffer! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
pin: pin mode: mode
"Sends an individual Pin Mode message"
self port nextPutAll: (ByteArray with: FirmataConstants setPinMode with: pin with: mode).! !

!Firmata methodsFor: 'digital pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
setDigitalInputs: portNumber data: portData 
"Puts but masked On/Off data for a whole digital port into array"
	digitalInputData at: portNumber + 1 put: portData! !

!Firmata methodsFor: 'error control' stamp: 'GitHub 1/Aug/2017 12:33:41'!
controlConnection
	self isConnected
		ifFalse: [ ^ self error: 'Serial port is not connected' ]! !

!Firmata methodsFor: 'error control' stamp: 'GitHub 1/Aug/2017 12:33:41'!
controlFirmataInstallation
	"If Firmata is not installed I throw an error"

	self isFirmataInstalled
		ifFalse: [ ^ self
				error:
					'Firmata doesn''t seem to be installed.
Please use the Arduino IDE to upload the StandardFirmata sketch' ]! !

!Firmata methodsFor: 'connection' stamp: 'GitHub 1/Aug/2017 12:33:41'!
connectOnPort: portName baudRate: aNumber
	"If the port cant't be open it stores nil, this way we can know if it is
	connected by asking if port is nil.
	In windows we can't open a port using the port name, so I convert the
	string to an integer"
	self isConnected ifTrue: [^ self].
	port := SerialPort new baudRate: aNumber.
	portName isString ifFalse: [ 
		self error: 'Expected port name. E.g. ''/dev/ttyACM0''' ].
	port openPort: portName.
	
	self isConnected ifTrue: [
		self
			startSteppingProcess;
			controlFirmataInstallation ]! !

!Firmata methodsFor: 'connection' stamp: 'sf 12/Sep/2026 11:19:56'!
disconnect
	"Stop the background process and release the serial port. Safe to
	call multiple times and when the connection is already broken."
	self stopSteppingProcess.
	port ifNotNil: [
		[ port close ]
			on: Error
			do: [ :error | ] ].
	port := nil.
	self initializeVariables ! !

!Firmata methodsFor: 'connection' stamp: 'GitHub 1/Aug/2017 12:33:41'!
isConnected
^port notNil! !

!Firmata methodsFor: 'other commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
endSysex
"Sends an End Sysex message"
self port  nextPutAll: (ByteArray with: FirmataConstants endSysex  ).! !

!Firmata methodsFor: 'other commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
queryFirmware
"Send a Firmware Name and Version query"
self startSysex.
self port  nextPutAll: (ByteArray with: FirmataConstants reportFirmware ).! !

!Firmata methodsFor: 'other commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
queryVersion
"Send a version report query"
self port nextPutAll: (ByteArray with: FirmataConstants reportVersion ).! !

!Firmata methodsFor: 'other commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
startSysex
"Sends a Start Sysex message"
self port  nextPutAll: (ByteArray with: FirmataConstants startSysex  ).! !

!Firmata methodsFor: 'analog pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
activateAnalogPin: pinNumber 
	self analogPinReport: pinNumber onOff: 1.
! !

!Firmata methodsFor: 'analog pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
analogPinReport: pin onOff: onOff 
	"Sends a message to turn Analog Pin reportng on or off for a pin"
self port 
		nextPutAll: (ByteArray
				with: (FirmataConstants reportAnalog  bitOr: pin)
				with: onOff)! !

!Firmata methodsFor: 'analog pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
analogRead: pinNumber
"Returns an analog value for an individual Analog pin"
^analogInputData at: pinNumber + 1! !

!Firmata methodsFor: 'analog pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
deactivateAnalogPin: pinNumber 
	self analogPinReport: pinNumber onOff: 0! !

!Firmata methodsFor: 'analog pins' stamp: 'GitHub 1/Aug/2017 12:33:41'!
setAnalogInput: pin value: value
"Stores analog value data in array"
	analogInputData at: pin + 1 put: value! !

!Firmata class methodsFor: 'instance creation' stamp: 'GitHub 1/Aug/2017 12:33:41'!
onPort: portNumber baudRate: aNumber
	^ self new
		connectOnPort: portNumber baudRate: aNumber;
		yourself! !

!FirmataConstants class methodsFor: 'others' stamp: 'GitHub 1/Aug/2017 12:33:41'!
maxDataBytes
"Maximum number of data bytes in non-Sysex messages"
^32 ! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
analogMessage
"0xE0 send data for an analog pin (or PWM)"
^16rE0! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
digitalMessage
"0x90 send data for digital pin"
^16r90! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
endSysex
"0xF7 end a MIDI Sysex message"
^16rF7! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
reportAnalog
"0xC0 enable analog input by pin number"
^16rC0! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
reportDigital
"0xD0 enable digital input by port pair"
^16rD0! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
reportVersion
"0xF9 report protocol version"
^16rF9! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
setPinMode
"0xF4 set a pin to INPUT/OUTPUT/ANALOG/PWM/SERVO - 0/1/2/3/4"
^16rF4! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
startSysex
"0xF0 start a MIDI Sysex message"
^16rF0! !

!FirmataConstants class methodsFor: 'message commands' stamp: 'GitHub 1/Aug/2017 12:33:41'!
systemReset
"0xFF reset from MIDI"
^16rFF! !

!FirmataConstants class methodsFor: 'version numbers' stamp: 'GitHub 1/Aug/2017 12:33:41'!
firmataMajorVersion
"for non-compatible changes"
^2! !

!FirmataConstants class methodsFor: 'version numbers' stamp: 'GitHub 1/Aug/2017 12:33:41'!
firmataMinorVersion
"for backward compatible changes"
^0! !

!FirmataConstants class methodsFor: 'version numbers' stamp: 'GitHub 1/Aug/2017 12:33:41'!
versionBlickPin
"digital pin to blick version on"
^13! !

!FirmataConstants class methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
pinModeAnalog
"analog pin in analogInput mode"
^2! !

!FirmataConstants class methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
pinModeInput
^0! !

!FirmataConstants class methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
pinModeOutput
^1! !

!FirmataConstants class methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
pinModePwm
"digital pin in PWM output mode"
^3! !

!FirmataConstants class methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
pinModeServo 
"digital pin in Servo output mode"
^4! !

!FirmataConstants class methodsFor: 'pin modes' stamp: 'GitHub 1/Aug/2017 12:33:41'!
pinModeUnavailable
	^ -1! !

!FirmataConstants class methodsFor: 'extended command set using Sysex' stamp: 'GitHub 1/Aug/2017 12:33:41'!
firmataString
"0x71 a string message with 14-bits per character"
^16r71! !

!FirmataConstants class methodsFor: 'extended command set using Sysex' stamp: 'GitHub 1/Aug/2017 12:33:41'!
reportFirmware
"0x79 report name and version of the firmware"
^16r79! !

!FirmataConstants class methodsFor: 'extended command set using Sysex' stamp: 'GitHub 1/Aug/2017 12:33:41'!
servoConfig
"0x70 set maximum angle, minPulse, maxPulse, frequency"
^16r70! !

!FirmataConstants class methodsFor: 'extended command set using Sysex' stamp: 'GitHub 1/Aug/2017 12:33:41'!
sysexNonRealtime
"0x7E MIDI reserved for non-realtime messages"
^16r7E! !

!FirmataConstants class methodsFor: 'extended command set using Sysex' stamp: 'GitHub 1/Aug/2017 12:33:41'!
sysexRealtime
"0x7F MIDI reserved for realtime messages"
^16r7F! !
