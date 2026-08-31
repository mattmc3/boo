namespace Boo.Lang.Lsp.Server

import System
import System.Threading
import Boo.Lang.Lsp.Workspace

callable AnalysisRequested(document as TextDocument)

class AnalysisWorker:
"""
Runs compilation on one background thread, off the message loop.

Binding a project costs hundreds of milliseconds once it is large enough, and
the compiler is not reentrant, so compilation happens here, one document at a
time, while the message loop stays free to read the next keystroke.

A submission waits out a debounce before it is compiled, so a burst of
keystrokes costs one compile rather than one per character.
"""

	_analyze as AnalysisRequested
	_debounce as int
	_queue = AnalysisQueue()
	_wakeup = AutoResetEvent(false)
	_idle = ManualResetEvent(true)
	_thread as Thread
	_running = false

	def constructor(analyze as AnalysisRequested, debounceMilliseconds as int):
		_analyze = analyze
		_debounce = debounceMilliseconds

	IsRunning as bool:
		get: return _running

	def Start():
		return if _running
		_running = true
		_thread = Thread(Loop)
		_thread.IsBackground = true
		_thread.Name = "boolsp analysis"
		_thread.Start()

	def Stop():
		return unless _running
		_running = false
		_wakeup.Set()
		_thread.Join(2000)

	def Submit(document as TextDocument):
		_idle.Reset()
		_queue.Submit(document)
		_wakeup.Set()

	def Withdraw(uri as string):
		_queue.Withdraw(uri)

	def WaitForIdle(timeoutMilliseconds as int) as bool:
	"""Waits for the queue to empty. For tests; nothing in the server waits."""
		return _idle.WaitOne(timeoutMilliseconds)

	private def Loop():
		while _running:
			_wakeup.WaitOne()
			break unless _running

			# Let a burst of keystrokes settle before paying for a compile.
			Thread.Sleep(_debounce)

			for document in _queue.Drain():
				break unless _running
				Analyze(document)

			_idle.Set() if _queue.Count == 0

	private def Analyze(document as TextDocument):
		try:
			_analyze(document)
		except e as Exception:
			# One bad document must not take the worker down with it.
			Console.Error.WriteLine("boolsp: analyzing ${document.Uri} failed: ${e}")
