if vim.b.current_syntax then
	return
end

local function syn(cmd)
	vim.api.nvim_buf_call(0, function()
		vim.cmd(cmd)
	end)
end

local keywords = {
	{ "booKeyword", {
		"break", "continue", "do", "elif", "else", "end", "ensure", "except",
		"failure", "for", "goto", "if", "in", "raise", "return", "then", "try",
		"unless", "while", "yield", "pass",
	} },
	{ "booOperatorWord", {
		"and", "as", "cast", "from", "import", "is", "isa", "namespace", "new",
		"not", "of", "or", "typeof",
	} },
	{ "booStorage", {
		"class", "constructor", "def", "destructor", "enum", "event",
		"interface", "struct",
	} },
	{ "booModifier", {
		"abstract", "final", "get", "internal", "override", "partial",
		"private", "protected", "public", "ref", "set", "static", "transient",
		"virtual",
	} },
	{ "booType", {
		"bool", "byte", "callable", "char", "date", "decimal", "double",
		"duck", "int", "long", "object", "regex", "sbyte", "short", "single",
		"string", "timespan", "uint", "ulong", "ushort", "void",
	} },
	{ "booBoolean", { "true", "false" } },
	{ "booNull", { "null" } },
	{ "booSelf", { "self", "super" } },
	{ "booBuiltin", {
		"array", "cat", "enumerate", "gets", "iterator", "join", "len", "map",
		"matrix", "print", "prompt", "quack", "range", "reversed", "shell",
		"shellp", "zip", "__addressof__", "__default__", "__initobj__",
		"__switch__",
	} },
	{ "booMacro", {
		"assert", "case", "checked", "debug", "ifdef", "initialization",
		"lock", "match", "normalArrayIndexing", "order", "otherwise",
		"preserving", "preservingLexicalInfo", "print", "property",
		"rawArrayIndexing", "unchecked", "unsafe", "using", "var", "yieldAll",
	} },
}

for _, entry in ipairs(keywords) do
	syn("syntax keyword " .. entry[1] .. " " .. table.concat(entry[2], " "))
end

syn([[syntax keyword booTodo contained TODO FIXME XXX WARNING]])

syn([[syntax match booComment "#.*$" contains=booTodo,@Spell]])
syn([[syntax match booComment "//.*$" contains=booTodo,@Spell]])
syn([[syntax region booComment start="/\*" end="\*/" contains=booTodo,@Spell]])

syn([[syntax match booEscape contained "\\."]])
syn([[syntax region booInterp contained matchgroup=booInterpDelim start="${" end="}" contains=TOP]])
syn([[syntax region booString start=+"""+ end=+"""+ contains=@Spell]])
syn([[syntax region booString start=+"+ skip=+\\"+ end=+"+ contains=booEscape,booInterp]])
syn([[syntax region booString start=+'+ skip=+\\'+ end=+'+ contains=booEscape]])
syn([[syntax match booRegex "@/\%(\\.\|[^/]\)*/"]])

syn([[syntax match booNumber "\<0[xX]\x\+\>"]])
syn([[syntax match booNumber "\<\d\+\%(\.\d\+\)\=\%([eE][-+]\=\d\+\)\=[lLfFdDmM]\=\>"]])

syn([==[syntax match booAttribute "^\s*\[\s*\zs\h\w*\%(\.\h\w*\)*\ze\s*[(,\]]"]==])
syn([[syntax match booAttribute "\[\%(assembly\|module\):\s*\zs\h\w*\%(\.\h\w*\)*"]])

syn([[syntax match booFunction "\%(\<def\s\+\|\<constructor\s\+\)\@<=\h\w*"]])
syn([[syntax match booTypeDef "\%(\<\%(class\|struct\|interface\|enum\)\s\+\)\@<=\h\w*"]])

local links = {
	booKeyword = "Keyword",
	booOperatorWord = "Operator",
	booStorage = "Structure",
	booModifier = "StorageClass",
	booType = "Type",
	booBuiltin = "Function",
	booMacro = "Macro",
	booBoolean = "Boolean",
	booNull = "Constant",
	booSelf = "Identifier",
	booComment = "Comment",
	booTodo = "Todo",
	booString = "String",
	booEscape = "SpecialChar",
	booInterpDelim = "Special",
	booRegex = "Special",
	booNumber = "Number",
	booAttribute = "PreProc",
	booFunction = "Function",
	booTypeDef = "Typedef",
}

for from, to in pairs(links) do
	vim.api.nvim_set_hl(0, from, { link = to, default = true })
end

vim.b.current_syntax = "boo"
