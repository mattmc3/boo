namespace Boo.Lang.Lsp.Tests.Server

import NUnit.Framework(TestFixtureAttribute, TestAttribute, Assert)
import Boo.Lang.Lsp.Server

[TestFixture]
class ServerInfoTestFixture:

	[Test]
	def NameIsTheExecutableName():
		assert ServerInfo.Name == "boolsp"

	[Test]
	def VersionComesFromTheAssembly():
		assert ServerInfo.Version is not null
		assert ServerInfo.Version.Length > 0
