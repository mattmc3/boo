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
	using System.Reflection.Emit;
	using System.Reflection.Metadata;
	using System.Reflection.Metadata.Ecma335;
	using System.Reflection.PortableExecutable;

	/// <summary>
	/// Turns a PersistedAssemblyBuilder into a PE image.
	/// </summary>
	/// <remarks>
	/// AssemblyBuilder.Save is gone and a runtime builder cannot be written out,
	/// so the image is always built here: EmitAssembly loads it when the caller
	/// wants to run the code, SaveAssembly writes it when there is an output file.
	/// Building it twice would renumber metadata, so the result is cached on the
	/// compiler context.
	/// </remarks>
	internal static class AssemblyImage
	{
		internal static byte[] Of(CompilerContext context, CompilerParameters parameters)
		{
			var cached = ContextAnnotations.GetAssemblyImage(context);
			if (cached != null)
				return cached;

			var builder = (PersistedAssemblyBuilder) ContextAnnotations.GetAssemblyBuilder(context);
			var metadata = builder.GenerateMetadata(out var ilStream, out var mappedFieldData);

			// Metadata tokens are only assigned by the call above, so the entry
			// point handle has to be read after it rather than before.
			var entryPoint = EntryPointHandle(context);

			var peBuilder = new ManagedPEBuilder(
				PEHeader(parameters),
				new MetadataRootBuilder(metadata),
				ilStream,
				mappedFieldData,
				entryPoint: entryPoint,
				flags: CorFlagsFor(parameters),
				// Nothing signs the image, so no space is reserved for a signature.
				strongNameSignatureSize: 0);

			var blob = new BlobBuilder();
			peBuilder.Serialize(blob);

			var image = blob.ToArray();
			ContextAnnotations.SetAssemblyImage(context, image);
			return image;
		}

		private static MethodDefinitionHandle EntryPointHandle(CompilerContext context)
		{
			var entryPoint = ContextAnnotations.GetEntryPointBuilder(context);
			return entryPoint == null
				? default(MethodDefinitionHandle)
				: MetadataTokens.MethodDefinitionHandle(entryPoint.MetadataToken);
		}

		private static PEHeaderBuilder PEHeader(CompilerParameters parameters)
		{
			var library = CompilerOutputType.Library == parameters.OutputType;
			return new PEHeaderBuilder(
				machine: TargetMachine(parameters),
				imageCharacteristics: library ? Characteristics.Dll : Characteristics.ExecutableImage,
				subsystem: CompilerOutputType.WindowsApplication == parameters.OutputType
					? Subsystem.WindowsGui
					: Subsystem.WindowsCui);
		}

		private static Machine TargetMachine(CompilerParameters parameters)
		{
			switch (parameters.Platform)
			{
				case "x86": return Machine.I386;
				case "x64": return Machine.Amd64;
				case "arm64": return Machine.Arm64;
				case "arm": return Machine.Arm;
				default: return Machine.Unknown; //anycpu
			}
		}

		private static CorFlags CorFlagsFor(CompilerParameters parameters)
		{
			// Requires32Bit marks a 32-bit-only image; everything else is plain IL
			// and lets the host decide.
			return "x86" == parameters.Platform
				? CorFlags.ILOnly | CorFlags.Requires32Bit
				: CorFlags.ILOnly;
		}
	}
}
