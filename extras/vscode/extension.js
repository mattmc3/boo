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

/**
 * The clone a built server sits in, or null if it came from PATH or a setting.
 *
 * The layout is the one BUILT_PATHS names: src/boolsp/bin/<config>/<tfm>.
 */
function repositoryOf(command) {
	const root = path.resolve(path.dirname(command), '..', '..', '..', '..', '..');
	return fs.existsSync(path.join(root, 'Boo.slnx')) ? root : null;
}

/** Build the server in a terminal, so its output is somewhere to look. */
function build(command, output) {
	const root = repositoryOf(command);
	if (!root) {
		vscode.window.showErrorMessage(
			`No Boo checkout around ${command} to build. Set boo.server.path.`);
		return;
	}
	output.appendLine(`building the server in ${root}`);
	const terminal = vscode.window.createTerminal({ name: 'Boo build', cwd: root });
	terminal.sendText('dotnet build Boo.slnx');
	terminal.show();
}

/**
 * Restart when the server executable changes.
 *
 * Rebuilding does not disturb the server already running: it holds the old
 * file open and goes on serving the old code until something restarts it.
 * Watching the directory rather than the file keeps the watch across a
 * delete and rewrite.
 */
function watchServer(context, command, output) {
	if (!vscode.workspace.getConfiguration('boo').get('server.restartOnChange')) return;

	const directory = path.dirname(command);
	const name = path.basename(command);
	if (!fs.existsSync(directory)) return;

	let pending;
	let watcher;
	try {
		watcher = fs.watch(directory, (event, changed) => {
			if (changed !== name) return;
			clearTimeout(pending);
			// A build writes it more than once, so wait for it to settle.
			pending = setTimeout(() => {
				if (!fs.existsSync(command)) return;
				output.appendLine('the server changed on disk, restarting it');
				client.restart().catch(error => output.appendLine(`could not restart it: ${error}`));
			}, 1500);
		});
	} catch (error) {
		output.appendLine(`not watching the server for changes: ${error}`);
		return;
	}

	// A build that removes the directory ends the watch; nothing to recover.
	watcher.on('error', error => output.appendLine(`stopped watching the server: ${error}`));
	context.subscriptions.push({ dispose: () => { clearTimeout(pending); watcher.close(); } });
}

function activate(context) {
	const folders = (vscode.workspace.workspaceFolders || []).map(f => f.uri.fsPath);
	const command = findServer(folders);
	const args = vscode.workspace.getConfiguration('boo').get('server.arguments') || [];

	const server = { command: command, args: args, transport: TransportKind.stdio };
	const output = vscode.window.createOutputChannel('Boo Language Server');
	output.appendLine(`starting the server: ${command}`);
	context.subscriptions.push(output);

	client = new LanguageClient('boo', 'Boo Language Server', { run: server, debug: server }, {
		documentSelector: [{ scheme: 'file', language: 'boo' }],
		synchronize: { fileEvents: vscode.workspace.createFileSystemWatcher('**/*.boo') },
		// The server reads these once, so changing one restarts it below.
		initializationOptions: {
			decompiler: vscode.workspace.getConfiguration('boo').get('decompiler.language'),
		},
		// Without this the client opens a second channel and everything the
		// server reports lands there instead of the one named Boo.
		outputChannel: output,
	});

	context.subscriptions.push(
		vscode.commands.registerCommand('boo.restartServer', async () => {
			await client.restart();
			vscode.window.showInformationMessage('Boo language server restarted.');
		}),
		// Pulling new sources leaves the built server behind them, and the
		// watch above restarts it once this lands.
		vscode.commands.registerCommand('boo.buildServer', () => build(command, output)));

	context.subscriptions.push(
		vscode.workspace.onDidChangeConfiguration(change => {
			if (!change.affectsConfiguration('boo.decompiler.language')) return;
			output.appendLine('the decompiler language changed, restarting the server');
			client.restart().catch(error => output.appendLine(`could not restart it: ${error}`));
		}));

	client.start().then(() => watchServer(context, command, output)).catch(error => {
		output.appendLine(`could not start it: ${error}`);
		vscode.window.showErrorMessage(
			`Could not start the Boo language server (${command}). ` +
			`Build it with "dotnet build Boo.slnx", or set boo.server.path. ${error}`,
			'Build it').then(chosen => { if (chosen) build(command, output); });
	});
}

function deactivate() {
	return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate, findServer };
