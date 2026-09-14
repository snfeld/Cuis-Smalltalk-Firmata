'From Cuis 7.8 of 2026 [latest update: #7977] on 12 September 2026 at 01:42:12 pm'!
'Tests for Firmata: protocol parsing, byte output and the connection
lifecycle (background process handling). Run without hardware using an
in-image mock port.'!
!provides: 'Tests-Firmata' 1 0!
!classDefinition: #FirmataTest category: #'Tests-Firmata'!
TestCase subclass: #FirmataTest
	instanceVariableNames: 'firmata port'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Tests-Firmata'!
!classDefinition: 'FirmataTest class' category: #'Tests-Firmata'!
FirmataTest class
	instanceVariableNames: ''!

!classDefinition: #FirmataPortMock category: #'Tests-Firmata'!
Object subclass: #FirmataPortMock
	instanceVariableNames: 'buffer written broken closed'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Tests-Firmata'!
!classDefinition: 'FirmataPortMock class' category: #'Tests-Firmata'!
FirmataPortMock class
	instanceVariableNames: ''!

!FirmataTest commentStamp: 'sf 12/Sep/2026 12:06:11' prior: 0!
I test the Firmata package against an in-image mock serial port, so no
Arduino hardware is needed.

Covered behaviors: parsing of the boot burst (protocol version and the
long REPORT_FIRMWARE sysex), the connection lifecycle (disconnect and a
broken serial channel must stop the background stepping process), and
the exact bytes sent for the most common protocol messages.!

!FirmataPortMock commentStamp: 'sf 12/Sep/2026 12:06:11' prior: 0!
I play the role of a serial port for Firmata tests. Incoming bytes are
queued in my buffer and answered by #readByteArray. Writes are recorded
in #written. #breakConnection simulates a failed connection: reads then
raise an error once the buffer is drained.!

!FirmataTest methodsFor: 'support' stamp: 'sf 12/Sep/2026 12:06:11'!
bootBurst
	"Protocol version report as StandardFirmata sends it: 0xF9 major minor"
	^ #[16rF9 2 5]! !

!FirmataTest methodsFor: 'support' stamp: 'sf 12/Sep/2026 12:06:11'!
bootBurstWithFirmware
	"REPORT_VERSION followed by the REPORT_FIRMWARE sysex that
	StandardFirmata sends when the board starts."
	| firmware result |
	firmware := self firmwareSysexForName: 'StandardFirmata.ino'.
	result := ByteArray new: 3 + firmware size.
	result at: 1 put: 16rF9; at: 2 put: 2; at: 3 put: 5.
	1 to: firmware size do: [ :i |
		result at: 3 + i put: (firmware at: i) ].
	^ result! !

!FirmataTest methodsFor: 'support' stamp: 'sf 12/Sep/2026 12:06:11'!
firmwareSysexForName: aName
	"REPORT_FIRMWARE sysex: 0xF0 0x79 <name as 14-bit characters>
	<major 7-bit> <minor 7-bit> 0xF7"
	| message |
	message := ByteArray new: 2 + (aName size * 2) + 3.
	message at: 1 put: 16rF0; at: 2 put: 16r79.
	1 to: aName size do: [ :i |
		| code |
		code := (aName at: i) codePoint.
		message at: (2 + ((i - 1) * 2) + 1) put: (code bitAnd: 127).
		message at: (2 + ((i - 1) * 2) + 2) put: ((code bitShift: -7) bitAnd: 127) ].
	message at: (2 + (aName size * 2) + 1) put: 2.
	message at: (2 + (aName size * 2) + 2) put: 5.
	message at: (2 + (aName size * 2) + 3) put: 16rF7.
	^ message! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
setUp
	"Each test gets a Firmata instance with an in-image mock port, so no
	hardware is needed."
	port := FirmataPortMock new.
	firmata := Firmata new.
	firmata instVarNamed: 'port' put: port! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
tearDown
	"Leave no background stepping process running across tests."
	firmata disconnect.
	(Delay forMilliseconds: 50) wait! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testBootBurstParsesProtocolVersion
	"StandardFirmata reports its protocol version on boot; it must be
	parsed without errors."
	port data: self bootBurst.
	firmata processInput.
	self assert: firmata isConnected.
	self assert: firmata majorVersion > 0.
	self assert: firmata minorVersion > 0! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testBootBurstIncludesLongFirmwareSysex
	"The REPORT_FIRMWARE sysex carries names longer than the old 33-byte
	buffer. It must not raise, and the sysex parsing state must be clean
	afterwards. Regression for the index-out-of-bounds crash."
	port data: self bootBurstWithFirmware.
	firmata processInput.
	self deny: (firmata instVarNamed: 'parsingSysex').
	self assert: firmata majorVersion > 0.
	self assert: firmata minorVersion > 0! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testFirmwareSysexWithVeryLongNameIsIgnoredSafely
	"Names beyond the maximum buffer size must be truncated, not cause
	an index error."
	port data: (self firmwareSysexForName: 'ThisIsAFirmwareNameThatIsFarLongerThanThirtyThreeBytesLong').
	firmata processInput.
	self deny: (firmata instVarNamed: 'parsingSysex').
	self assert: firmata isConnected! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testDisconnectStopsBackgroundProcess
	"#disconnect must terminate the stepping process and release the
	port. Regression: a leaked background process kept polling."
	firmata startSteppingProcess.
	(Delay forMilliseconds: 150) wait.
	firmata disconnect.
	(Delay forMilliseconds: 50) wait.
	self assert: firmata isConnected not.
	self assert: (firmata instVarNamed: 'steppingProcess') isNil! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testBrokenConnectionStopsBackgroundProcess
	"When the serial channel fails, #step drops the port and the
	stepping process must end by itself."
	firmata startSteppingProcess.
	(Delay forMilliseconds: 100) wait.
	port breakConnection.
	(Delay forMilliseconds: 300) wait.
	self assert: firmata isConnected not.
	self assert: (firmata instVarNamed: 'steppingProcess') isNil! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testDisconnectIsIdempotent
	"#disconnect must be safe to call repeatedly and when the connection
	is already closed."
	self shouldnt: [ firmata disconnect ] raise: Error.
	firmata startSteppingProcess.
	(Delay forMilliseconds: 50) wait.
	firmata disconnect.
	self shouldnt: [ firmata disconnect ] raise: Error.
	self assert: firmata isConnected not! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testDisconnectResetsVersionState
	"#disconnect must clear the parsed protocol state."
	port data: self bootBurst.
	firmata processInput.
	self assert: firmata version > 0.
	firmata disconnect.
	self assert: firmata version = 0! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testDigitalWriteSendsProtocolBytes
	"Digital write on pin 13 must produce the exact Firmata message."
	firmata digitalWrite: 13 value: 1.
	self assert: port written equals: #[145 32 0]! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testAnalogWriteSendsPwmBytes
	"Analog (PWM) write on pin 3 must produce the exact Firmata message."
	firmata analogWrite: 3 value: 200.
	self assert: port written equals: #[227 72 1]! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testAnalogReadParsesFourteenBitValue
	"Analog values travel as two 7-bit bytes, least significant first."
	port data: #[16rE0 45 1].
	firmata processInput.
	self assert: (firmata analogRead: 0) equals: 173! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testQueryVersionSendsReportVersionMessage
	firmata queryVersion.
	self assert: port written equals: #[16rF9]! !

!FirmataTest methodsFor: 'testing' stamp: 'sf 12/Sep/2026 12:06:11'!
testPinModeSendsSetPinModeMessage
	firmata pin: 13 mode: FirmataConstants pinModeOutput.
	self assert: port written equals: #[16rF4 13 1]! !

!FirmataPortMock methodsFor: 'initialize-release' stamp: 'sf 12/Sep/2026 12:06:11'!
initialize
	buffer := ByteArray new.
	written := ByteArray new.
	broken := false.
	closed := false! !

!FirmataPortMock methodsFor: 'accessing' stamp: 'sf 12/Sep/2026 12:06:11'!
data: aByteArray
	"Bytes the next #readByteArray answers"
	buffer := aByteArray! !

!FirmataPortMock methodsFor: 'accessing' stamp: 'sf 12/Sep/2026 12:06:11'!
appendData: aByteArray
	"Add more incoming bytes"
	buffer := buffer , aByteArray! !

!FirmataPortMock methodsFor: 'accessing' stamp: 'sf 12/Sep/2026 12:06:11'!
breakConnection
	"Simulate a broken serial connection: once the buffer is drained,
	every read raises an error."
	broken := true! !

!FirmataPortMock methodsFor: 'accessing' stamp: 'sf 12/Sep/2026 12:06:11'!
written
	^ written! !

!FirmataPortMock methodsFor: 'accessing' stamp: 'sf 12/Sep/2026 12:06:11'!
isClosed
	^ closed! !

!FirmataPortMock methodsFor: 'serial protocol' stamp: 'sf 12/Sep/2026 12:06:11'!
readByteArray
	buffer size > 0
		ifTrue: [ | result |
			result := buffer.
			buffer := ByteArray new.
			^ result ].
	broken
		ifTrue: [ self error: 'simulated serial failure' ].
	^ ByteArray new! !

!FirmataPortMock methodsFor: 'serial protocol' stamp: 'sf 12/Sep/2026 12:06:11'!
nextPutAll: aByteArray
	written := written , aByteArray! !

!FirmataPortMock methodsFor: 'serial protocol' stamp: 'sf 12/Sep/2026 12:06:11'!
close
	closed := true! !
