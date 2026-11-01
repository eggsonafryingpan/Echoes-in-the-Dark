// Slow a rendered line down without changing its pitch.
//
//   swift stretch.swift <in.aiff> <out.aiff> <rate>
//
// rate < 1 is slower (0.85 = 85% speed). Used by generate_voices.sh because
// the neural voices (Joelle) all but ignore `say -r`; this is Apple's own
// time-stretch (AVAudioUnitTimePitch), rendered offline.

import AVFoundation

let args = CommandLine.arguments
guard args.count == 4, let rate = Float(args[3]) else {
	FileHandle.standardError.write("usage: stretch.swift <in> <out> <rate>\n".data(using: .utf8)!)
	exit(2)
}

let input = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
let format = input.processingFormat

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let timePitch = AVAudioUnitTimePitch()
timePitch.rate = rate
timePitch.overlap = 16  // smoother on speech than the default 8

engine.attach(player)
engine.attach(timePitch)
engine.connect(player, to: timePitch, format: format)
engine.connect(timePitch, to: engine.mainMixerNode, format: format)
try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
try engine.start()
player.scheduleFile(input, at: nil)
player.play()

let output = try AVAudioFile(forWriting: URL(fileURLWithPath: args[2]), settings: input.fileFormat.settings)
let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
// The stretched clip is longer than the source, plus a little tail so the
// last word's decay isn't clipped.
let total = AVAudioFramePosition(Double(input.length) / Double(rate)) + AVAudioFramePosition(format.sampleRate * 0.25)

while engine.manualRenderingSampleTime < total {
	let frames = min(AVAudioFrameCount(total - engine.manualRenderingSampleTime), buffer.frameCapacity)
	let status = try engine.renderOffline(frames, to: buffer)
	guard status == .success else {
		FileHandle.standardError.write("render stopped: \(status.rawValue)\n".data(using: .utf8)!)
		exit(1)
	}
	try output.write(from: buffer)
}
engine.stop()
// Globals are never deinitialized at exit, so the file must be closed by
// hand or its header is never finalized and it reads as empty.
output.close()
