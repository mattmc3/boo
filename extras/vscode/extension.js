const fs = require('fs');
const path = require('path');
const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

let client;

// Where a boolsp built from source lands, relative to a clone of the repo.
const BUILT_PATHS = [
	path.join('src', 'boolsp', 'bin', 'Debug', 'net10.0', 'boolsp'),
	path.join('src', 'boolsp', 'bin', 'Release', 'net10.0', 'boolsp'),
];

function executable(name) {
	return process.platform === 'win32' ? name + '.exe' : name;
}

/**
 * The server to run: whatever the setting names, else a build under one of the
 * open folders, else one next to this extension, else boolsp on PATH.
 *
 * The extension ships inside the repository it builds from, so the last search
 * finds the server even when the window has no folder open at all.
 */
function findServer(folders) {
	const configured = vscode.workspace.getConfiguration('boo').get('server.path');
	if (configured) return configured;

	const roots = (folders || []).concat([path.resolve(__dirname, '..', '..')]);
	for (const root of roots) {
		for (const candidate of BUILT_PATHS) {
			const full = path.join(root, executable(candidate));
			if (fs.existsSync(full)) return full;
		}
	}
	return executable('boolsp');
}

function activate(context) {
	const folders = (vscode.workspace.workspaceFolders || []).map(f => f.uri.fsPath);
	const command = findServer(folders);
	const args = vscode.workspace.getConfiguration('boo').get('server.arguments') || [];

	const server = { command: command, args: args, transport: TransportKind.stdio };
	const output = vscode.window.createOutputChannel('Boo');
	output.appendLine(`starting the server: ${command}`);
	context.subscriptions.push(output);

	client = new LanguageClient('boo', 'Boo Language Server', { run: server, debug: server }, {
		documentSelector: [{ scheme: 'file', language: 'boo' }],
		synchronize: { fileEvents: vscode.workspace.createFileSystemWatcher('**/*.boo') },
	});

	context.subscriptions.push(
		vscode.commands.registerCommand('boo.restartServer', async () => {
			await client.restart();
			vscode.window.showInformationMessage('Boo language server restarted.');
		}));

	client.start().catch(error => {
		output.appendLine(`could not start it: ${error}`);
		vscode.window.showErrorMessage(
			`Could not start the Boo language server (${command}). ` +
			`Build it with "dotnet build Boo.slnx", or set boo.server.path. ${error}`);
	});
}

function deactivate() {
	return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate, findServer };
