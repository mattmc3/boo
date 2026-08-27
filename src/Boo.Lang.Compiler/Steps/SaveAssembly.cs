#region license
// Copyright (c) 2004, Rodrigo B. de Oliveira (rbo@acm.org)
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
//     * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//     * Neither the name of Rodrigo B. de Oliveira nor the names of its
//     contributors may be used to endorse or promote products derived from this
//     software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#endregion

namespace Boo.Lang.Compiler.Steps
{
	using System;
	using System.IO;
	using System.Reflection;
	using System.Reflection.Emit;
	using System.Reflection.Metadata;
	using System.Reflection.Metadata.Ecma335;
	using System.Reflection.PortableExecutable;

	public class SaveAssembly : AbstractCompilerStep
	{
		override public void Run()
		{
			if (Errors.Count > 0)
				return;

			var builder = ContextAnnotations.GetAssemblyBuilder(Context) as PersistedAssemblyBuilder;
			if (builder == null)
				throw new InvalidOperationException("in-memory assemblies cannot be saved");

			// Tokens are only assigned once metadata exists, so the entry point
			// handle has to be read after this call rather than before.
			var metadata = builder.GenerateMetadata(out var ilStream, out var mappedFieldData);
			var entryPoint = EntryPointHandle();

			var peBuilder = new ManagedPEBuilder(
				PEHeader(),
				new MetadataRootBuilder(metadata),
				ilStream,
				mappedFieldData,
				entryPoint: entryPoint,
				flags: CorFlags(),
				// Nothing signs the image, so no space is reserved for a signature.
				strongNameSignatureSize: 0);

			var blob = new BlobBuilder();
			peBuilder.Serialize(blob);

			var image = blob.ToArray();
			File.WriteAllBytes(Context.GeneratedAssemblyFileName, image);

			// A persisted builder cannot be executed, so anything downstream that
			// wants to run the code gets the assembly from the image just written.
			// Loading the bytes rather than the path matters: callers that compile
			// repeatedly reuse one output file, and LoadFrom would keep handing
			// back the first assembly loaded from it.
			if (Parameters.GenerateInMemory)
				Context.GeneratedAssembly = Assembly.Load(image);
		}

		MethodDefinitionHandle EntryPointHandle()
		{
			var entryPoint = ContextAnnotations.GetEntryPointBuilder(Context);
			return entryPoint == null
				? default(MethodDefinitionHandle)
				: MetadataTokens.MethodDefinitionHandle(entryPoint.MetadataToken);
		}

		PEHeaderBuilder PEHeader()
		{
			var library = CompilerOutputType.Library == Parameters.OutputType;
			return new PEHeaderBuilder(
				machine: TargetMachine(),
				imageCharacteristics: library ? Characteristics.Dll : Characteristics.ExecutableImage,
				subsystem: CompilerOutputType.WindowsApplication == Parameters.OutputType
					? Subsystem.WindowsGui
					: Subsystem.WindowsCui);
		}

		Machine TargetMachine()
		{
			switch (Parameters.Platform)
			{
				case "x86": return Machine.I386;
				case "x64": return Machine.Amd64;
				case "arm64": return Machine.Arm64;
				case "arm": return Machine.Arm;
				default: return Machine.Unknown; //anycpu
			}
		}

		CorFlags CorFlags()
		{
			// Requires32Bit is what marks a 32-bit-only image; everything else is
			// plain IL and lets the host pick.
			return "x86" == Parameters.Platform
				? System.Reflection.PortableExecutable.CorFlags.ILOnly | System.Reflection.PortableExecutable.CorFlags.Requires32Bit
				: System.Reflection.PortableExecutable.CorFlags.ILOnly;
		}
	}
}
