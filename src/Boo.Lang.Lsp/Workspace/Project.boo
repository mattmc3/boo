namespace Boo.Lang.Lsp.Workspace

import System
import System.Collections.Generic
import System.IO
import System.Xml
import Boo.Lang.Lsp.Json

class Project:
"""
The project a source file belongs to.

A .boo file on its own compiles against nothing but the default assemblies,
so anything the project references is unresolved. Finding the project file is
the first step out of that.
"""

	static def Find(sourcePath as string) as string:
	"""
	The nearest .booproj at or above the file, or null if there is none.

	Nearest wins: a project in an inner directory owns the files under it even
	when an outer directory has one too.
	"""
		return null if string.IsNullOrEmpty(sourcePath)
		directory = Path.GetDirectoryName(Path.GetFullPath(sourcePath))
		while not string.IsNullOrEmpty(directory) and Directory.Exists(directory):
			projects = Directory.GetFiles(directory, "*.booproj")
			if projects.Length > 0:
				System.Array.Sort(projects)
				return projects[0]
			directory = Path.GetDirectoryName(directory)
		return null

	static def FindForDocument(uri as string) as string:
	"""
	The project behind a document the client named, or null.

	A document with no file behind it, such as an unsaved buffer, belongs to
	no project.
	"""
		return Find(PathOf(uri))

	static def PathOf(uri as string) as string:
	"""The file a document URI names, or null if it names no file."""
		parsed as Uri
		return null if not Uri.TryCreate(uri, UriKind.Absolute, parsed)
		return null if not parsed.IsFile
		return parsed.LocalPath

	static def UriOf(fileName as string) as string:
	"""
	The URI for a file the compiler named, or the name unchanged if it is
	already one.

	The open document is compiled from text the client named with a URI, and
	the files beside it are compiled from disk and carry a path, so what a
	node reports is one or the other. Only a URI is an answer the protocol
	takes.
	"""
		return fileName if string.IsNullOrEmpty(fileName)
		parsed as Uri
		return fileName if Uri.TryCreate(fileName, UriKind.Absolute, parsed) and not parsed.IsFile
		try:
			return Uri(fileName).AbsoluteUri
		except:
			# Whatever it is, it is not a file, so leave it as it came.
			return fileName

	static def SourceFiles(projectPath as string) as List[of string]:
	"""
	Every .boo file the project compiles.

	The glob matches what Boo.targets builds: everything below the project
	directory, less the build output.
	"""
		sources = List[of string]()
		return sources if string.IsNullOrEmpty(projectPath)
		directory = Path.GetDirectoryName(Path.GetFullPath(projectPath))
		return sources if not Directory.Exists(directory)
		for file in Directory.GetFiles(directory, "*.boo", SearchOption.AllDirectories):
			sources.Add(file) unless IsBuildOutput(directory, file)
		sources.Sort()
		return sources

	private static def IsBuildOutput(root as string, file as string) as bool:
		relative = file.Substring(root.Length).TrimStart(Path.DirectorySeparatorChar)
		head = relative.Split(Path.DirectorySeparatorChar)[0]
		return head == "bin" or head == "obj"

	static def ProjectReferences(projectPath as string) as List[of string]:
	"""
	The projects this one references, as full paths, in the order written.

	A reference marked ReferenceOutputAssembly="false" is a build ordering
	hint and produces nothing to compile against, so it is left out.
	"""
		references = List[of string]()
		document = Load(projectPath)
		return references if document is null
		directory = Path.GetDirectoryName(Path.GetFullPath(projectPath))
		for node in document.GetElementsByTagName("ProjectReference"):
			element = node as XmlElement
			continue if element is null
			continue if element.GetAttribute("ReferenceOutputAssembly").ToLowerInvariant() == "false"
			include = element.GetAttribute("Include")
			continue if string.IsNullOrEmpty(include)
			references.Add(Path.GetFullPath(Path.Combine(directory, Relative(include))))
		return references

	private static def Relative(include as string) as string:
	"""An Include as MSBuild writes it, in this platform's separators."""
		return include.Replace(char('\\'), Path.DirectorySeparatorChar).Replace(char('/'), Path.DirectorySeparatorChar)

	private static def Load(projectPath as string) as XmlDocument:
	"""The project as XML, or null if it is missing or malformed."""
		return null if string.IsNullOrEmpty(projectPath) or not File.Exists(projectPath)
		try:
			document = XmlDocument()
			document.Load(projectPath)
			return document
		except:
			# A project half way through an edit is normal, not an error.
			return null

	static def OutputAssembly(projectPath as string) as string:
	"""
	The assembly the project last built, or null if it has not been built.

	Which configuration is nobody's decision to make: the newest build under
	bin is the one the developer is working against.
	"""
		return null if string.IsNullOrEmpty(projectPath) or not File.Exists(projectPath)
		directory = Path.GetDirectoryName(Path.GetFullPath(projectPath))
		output = Path.Combine(directory, "bin")
		return null if not Directory.Exists(output)
		newest as string = null
		stamp = DateTime.MinValue
		for candidate in Directory.GetFiles(output, AssemblyName(projectPath) + ".dll", SearchOption.AllDirectories):
			written = File.GetLastWriteTimeUtc(candidate)
			continue if newest is not null and written <= stamp
			newest = candidate
			stamp = written
		return newest

	private static def AssemblyName(projectPath as string) as string:
	"""What the project calls its assembly, which defaults to its own name."""
		document = Load(projectPath)
		if document is not null:
			for node in document.GetElementsByTagName("AssemblyName"):
				text = (node as XmlNode).InnerText.Trim()
				return text if text.Length > 0
		return Path.GetFileNameWithoutExtension(projectPath)

	static def References(projectPath as string) as List[of string]:
	"""
	The assemblies to compile the project against.

	A build copies every project it references next to its own output, so the
	newest output directory is the reference set, less the project's own
	assembly: compiling sources against a stale copy of themselves would
	report every type in them as defined twice.

	A project that has been restored but not built has no output directory,
	and its packages are still on disk where restore left them. Those are
	worth having on their own: a file opened in a project nobody has built
	yet otherwise sees no references at all. What the projects it references
	built covers the rest of that case, since a solution is usually part
	built rather than not built at all.

	One assembly per file name, and the copy beside the output wins: those
	are the ones the build agreed on, and the same type offered twice is the
	same error as compiling a project against itself.
	"""
		references = List[of string]()
		return references if string.IsNullOrEmpty(projectPath) or not File.Exists(projectPath)

		seen = HashSet[of string]()
		own = OutputAssembly(projectPath)
		if own is not null:
			# Its own assembly is claimed rather than added: compiling the
			# sources against a stale copy of themselves would report every
			# type in them as defined twice.
			seen.Add(Path.GetFileName(own))
			for candidate in Directory.GetFiles(Path.GetDirectoryName(own), "*.dll"):
				Take(references, seen, candidate)

		for referenced in ProjectReferences(projectPath):
			built = OutputAssembly(referenced)
			Take(references, seen, built) if built is not null

		for package in PackageAssemblies(projectPath):
			Take(references, seen, package)

		references.Sort()
		return references

	private static def Take(references as List[of string], seen as HashSet[of string], path as string):
	"""Keep an assembly unless one of that name is already spoken for."""
		references.Add(path) if seen.Add(Path.GetFileName(path))

	private static def PackageAssemblies(projectPath as string) as List[of string]:
	"""
	The package assemblies restore wrote into the assets file.

	A build does not copy these next to its output, so the output directory
	alone leaves out everything the project takes from NuGet. Projects listed
	there are skipped: those are already beside the output.
	"""
		assemblies = List[of string]()
		directory = Path.GetDirectoryName(Path.GetFullPath(projectPath))
		assets = Read(Path.Combine(directory, "obj", "project.assets.json"))
		return assemblies if assets is null
		folder = First(Section(assets, "packageFolders"))
		return assemblies if folder is null
		libraries = Section(assets, "libraries")
		for framework in Section(assets, "targets").Values:
			for entry in (framework as Dictionary[of string, object]):
				package = entry.Value as Dictionary[of string, object]
				continue if package is null or package["type"] as string != "package"
				path = (libraries[entry.Key] as Dictionary[of string, object])["path"] as string
				continue if path is null
				for compiled in Section(package, "compile").Keys:
					continue if Path.GetFileName(compiled) == "_._"
					full = Path.Combine(folder, Relative(path), Relative(compiled))
					assemblies.Add(full) if File.Exists(full)
		return assemblies

	private static def Read(path as string) as Dictionary[of string, object]:
	"""The file as a JSON object, or null if it is missing or malformed."""
		return null if not File.Exists(path)
		try:
			return JsonCodec.Parse(File.ReadAllText(path)) as Dictionary[of string, object]
		except:
			return null

	private static def Section(owner as Dictionary[of string, object], name as string) as Dictionary[of string, object]:
	"""One nested object, or an empty one so callers need not check."""
		value as object
		if owner.TryGetValue(name, value):
			nested = value as Dictionary[of string, object]
			return nested if nested is not null
		return Dictionary[of string, object]()

	private static def First(owner as Dictionary[of string, object]) as string:
		for key in owner.Keys:
			return key
		return null
