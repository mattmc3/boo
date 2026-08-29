namespace BooCompiler.Tests
{
	using System;
	using System.IO;
	using System.Text;
	using System.Threading;

	/// <summary>
	/// Console.Out is one slot for the whole process, so a fixture that calls
	/// Console.SetOut takes it from every other fixture. This installs a single
	/// writer that dispatches to whatever the calling context asked for, so
	/// fixtures can capture their own output at the same time.
	///
	/// The target is AsyncLocal rather than ThreadStatic because a testcase can
	/// continue on another thread, and AsyncLocal follows it.
	/// </summary>
	public sealed class ConsoleFanOut : TextWriter
	{
		private static readonly AsyncLocal<TextWriter> Target = new AsyncLocal<TextWriter>();
		private static readonly AsyncLocal<TextReader> Input = new AsyncLocal<TextReader>();

		private static TextWriter _fallbackOut;
		private static TextReader _fallbackIn;
		private static int _installed;

		public static void Install()
		{
			if (Interlocked.Exchange(ref _installed, 1) == 1)
				return;

			_fallbackOut = Console.Out;
			_fallbackIn = Console.In;
			Console.SetOut(new ConsoleFanOut());
			Console.SetIn(new FanOutReader());
		}

		/// <summary>
		/// Sends console writes on this context to <paramref name="output"/>, and
		/// reads from <paramref name="input"/>, until the result is disposed.
		/// </summary>
		public static IDisposable Redirect(TextWriter output, TextReader input)
		{
			var previousOut = Target.Value;
			var previousIn = Input.Value;
			Target.Value = output;
			Input.Value = input;
			return new Restore(previousOut, previousIn);
		}

		private sealed class Restore : IDisposable
		{
			private readonly TextWriter _out;
			private readonly TextReader _in;

			public Restore(TextWriter output, TextReader input)
			{
				_out = output;
				_in = input;
			}

			public void Dispose()
			{
				Target.Value = _out;
				Input.Value = _in;
			}
		}

		private static TextWriter Current
		{
			get { return Target.Value ?? _fallbackOut; }
		}

		public override Encoding Encoding
		{
			get { return Encoding.UTF8; }
		}

		public override void Write(char value)
		{
			Current.Write(value);
		}

		public override void Write(string value)
		{
			Current.Write(value);
		}

		public override void WriteLine(string value)
		{
			Current.WriteLine(value);
		}

		public override void WriteLine()
		{
			Current.WriteLine();
		}

		public override void Write(char[] buffer, int index, int count)
		{
			Current.Write(buffer, index, count);
		}

		public override void Flush()
		{
			Current.Flush();
		}

		private sealed class FanOutReader : TextReader
		{
			private static TextReader Current
			{
				get { return Input.Value ?? _fallbackIn; }
			}

			public override int Read()
			{
				return Current.Read();
			}

			public override int Peek()
			{
				return Current.Peek();
			}

			public override string ReadLine()
			{
				return Current.ReadLine();
			}

			public override string ReadToEnd()
			{
				return Current.ReadToEnd();
			}
		}
	}
}
