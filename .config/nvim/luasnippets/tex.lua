local ls = require "luasnip"
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node

local l = require("luasnip.extras").lambda
local m = require("luasnip.extras").match
local events = require("luasnip.util.events")

local ts = require "vim.treesitter"
local query = require "vim.treesitter.query"
local ts_utils = require "nvim-treesitter.ts_utils"
local tex = {}

tex.conds = {}
function tex.conds.args_to_string(args)
	return table.concat(args, "\n") -- not [1]?
end

function tex.conds.is_empty(args)
	local str = tex.conds.args_to_string(args[1])
	return str == ""
end

function tex.conds.is_atom(args)
	local str = tex.conds.args_to_string(args[1])
	return str:find("^[^\\{}%[%]]$") or str:match("^\\%w+$")
end

function tex.conds.current_nodes()
	local node = ts_utils.get_node_at_cursor()
	local buf = vim.api.nvim_get_current_buf()
	return function ()
		if node then
			local current_node = node
			-- traverse up
			node = node:parent()
			return current_node, buf
		end
	end
end

-- if the current node corresponds to a latex command, returns the name of the command
-- includes the backslash!
function tex.conds.get_command_name(node, buf)
	local cmd_node = node:field "command" [1]
	if cmd_node then
		return query.get_node_text(cmd_node, buf)
	end
end

-- if the given node corresponds to a latex environment, return the name of the environment
function tex.conds.get_environment_name(node, buf)
	local begin_node = node:field "begin" [1]
	local curly_node = begin_node and begin_node:field "name" [1]
	local name_node = curly_node and curly_node:field "text" [1]

	if name_node then
		return query.get_node_text(name_node, buf)
	end
end

-- returns whether the cursor is currently in the given set of environments
-- envs is a dictionary of latex environment names corresponding to a boolean value
-- returns the boolean value corresponding to the first environment found
function tex.conds.in_environments(envs)
	for node, buf in tex.conds.current_nodes() do
		local env_name = tex.conds.get_environment_name(node, buf)
		if env_name and envs[env_name] ~= nil then
			return envs[env_name], env_name
		end
	end
	return false
end

-- a convenience function for tex.conds.in_environments for a single environment
function tex.conds.in_environment(env)
	return tex.conds.in_environments({ [env] = true })
end

-- returns whether the cursor is currently in a maths environment
function tex.conds.in_maths()
	local maths_nodes = {
		["math_environment"] = true,
		["displayed_equation"] = true,
		["inline_formula"] = true,
		["text_mode"] = false,
	}
	local maths_envs = {
		["tikzcd"] = true,
	}
	local maths_cmds = {
	}

	for node, buf in tex.conds.current_nodes() do
		local env_name = tex.conds.get_environment_name(node, buf)
		local cmd_name = tex.conds.get_command_name(node, buf)
		if maths_nodes[node:type()] ~= nil then
			return maths_nodes[node:type()]
		elseif env_name and maths_envs[env_name] ~= nil then
			return maths_envs[env_name]
		elseif cmd_name and maths_cmds[cmd_name] ~= nil then
			return maths_cmds[cmd_name]
		end
	end
	return false
end

-- returns whether the cursor is currently in an aligned environment (which uses &s)
function tex.conds.in_aligned()
	return tex.conds.in_environments({
		["align"] = true,
		["align*"] = true,
		["tikzcd"] = true,
		["cases"] = true,
		["gather"] = true,
		-- tabular
	})
end

function tex.conds.in_list()
	return tex.conds.in_environments({
		["itemize"] = true,
		["enumerate"] = true,
		["description"] = true,
	})
end

function tex.conds.not_in_maths()
	return not tex.conds.in_maths()
end

function tex.conds.in_commutative_diagram()
	return tex.conds.in_environment("tikzcd")
end

function tex.conds.starts_line(line, trigger, captures)
	return line:find("^%s*" .. trigger) and true or false
end

tex.snip = {}
tex.snip.snippets = {}
tex.snip.autosnippets = {}

tex.snip.is_gobbling = false
tex.snip.gobble_autocmd = nil
function tex.snip.gobble_space_before_insert()
	if tex.snip.gobble_autocmd then vim.api.nvim_del_autocmd(tex.snip.gobble_autocmd) end
	tex.snip.gobble_autocmd = vim.api.nvim_create_autocmd({ "CursorMoved", "InsertCharPre" }, {
		callback = function (...)
			if vim.v.char:match("[%w\\]") then
				vim.v.char = " " .. vim.v.char
			end
			if tex.snip.gobble_autocmd then vim.api.nvim_del_autocmd(tex.snip.gobble_autocmd) end
			tex.snip.gobble_autocmd = nil
			return true
		end,
		buffer = 0,
		once = true,
		desc = "Add space after expanding snippet"
	})
end

function tex.snip.delimiter(pos, open, close, placeholder)
	return sn(pos, { t { open }, i(1, placeholder), t { close }}, {})
end	

function tex.snip.conditional_delimiter(pos, fn, if_true, if_false, placeholder)
	return sn(pos, { 
		m(1, fn, if_true[1], if_false[1]), i(1, placeholder), m(1, fn, if_true[2], if_false[2]) 
		}, {})
end

function tex.snip.brackets(pos, num_brackets, placeholders)
	local subsnippets = {}
	local placeholders = placeholders or {}
	for j = 1, num_brackets do
		subsnippets[j] = tex.snip.delimiter(j, "{", "}", placeholders[j])
	end
	return sn(pos, subsnippets, {})
end

function tex.snip.optional_brackets(pos, num_brackets, placeholders)
	local subsnippets = {}
	local placeholders = placeholders or {}
	for j = 1, num_brackets do
		subsnippets[j] = tex.snip.conditional_delimiter(j, tex.conds.is_empty, { "", "" }, { "[", "]" }, placeholders[j])
	end
	return sn(pos, subsnippets, {})
end

function tex.snip.surround_in_maths(snippet, opts)
	local opts = opts or {}
	local pos = opts.pos or 1
	local insert_pos = #snippet.insert_nodes + 1
	return sn(pos, 
		{ 
			m({}, tex.conds.in_maths, "", "\\( "),
			snippet, 
			i(insert_pos),
			m({}, tex.conds.in_maths, "", " \\)"),
		},
		{
			callbacks = { [insert_pos] = {
				[events.enter] = tex.snip.gobble_space_before_insert
			}}
		}
	)
end

function tex.snip.shorthand(trigger, snippet, opts)
	local opts = opts or {}

	-- if the snippet is not triggered in a maths environment, add it in
	local ensure_maths = opts.ensure_maths or false
	local priority = opts.priority or 1000

	if ensure_maths then
		local in_maths_opts = vim.deepcopy(opts)
		local not_in_maths_opts = vim.deepcopy(opts)
		in_maths_opts.ensure_maths = false
		in_maths_opts.in_maths = true
		in_maths_opts.priority = priority + 1
		not_in_maths_opts.ensure_maths = false
		not_in_maths_opts.not_in_maths = true
		in_maths_opts.priority = priority 

		tex.snip.shorthand(trigger, vim.deepcopy(snippet), in_maths_opts) -- deepcopy avoids such a frustrating bug??? 
		tex.snip.shorthand(trigger, tex.snip.surround_in_maths(vim.deepcopy(snippet)), not_in_maths_opts)
		return 
	end

	-- expand the snippet even if it occurs in a word
	local in_word = opts.in_word or false
	local starts_line = opts.starts_line or false
	local in_maths = opts.in_maths or false
	local not_in_maths = opts.not_in_maths or false

	local condition = opts.condition or function () return true end
	local trigger_condition = function (line_to_cursor, matched_trigger, captures)
		if (not condition(line_to_cursor, matched_trigger, matches))
			or
			(starts_line and not line_to_cursor:match("^%s*" .. matched_trigger .. "$"))
			or
			(in_word and line_to_cursor:match("\\" .. matched_trigger .. "$"))
			or 
			(not in_word and line_to_cursor:match("[\\%w]" .. matched_trigger .. "$"))
			or
			(in_maths and tex.conds.not_in_maths())
			or
			(not_in_maths and tex.conds.in_maths())
		then
			return false
		end
		return true
	end

	-- expand the snippet as soon as it is typed, instead of waiting for a space (or other closing character)
	local immediate_expansion = opts.immediate_expansion or false
	local gobble_space = opts.gobble_space or false

	local callbacks = vim.deepcopy(opts.callbacks or {})
	if gobble_space then
		callbacks[-1] = callbacks[-1] or {}
		callbacks[-1][events.leave] = tex.snip.gobble_space_before_insert
	end

	local trigger_pattern = trigger .. (immediate_expansion and "()" or "([%s{}%[%]%.,:;:\\])")

	table.insert(tex.snip.autosnippets,
		s(
			{ trig = trigger_pattern, regTrig = true, wordTrig = false },
			{
				snippet,
				not immediate_expansion and (gobble_space and l(l.CAPTURE1:gsub("%s", "")) or l(l.CAPTURE1)) or nil,
			},
			{ 
				callbacks = callbacks,
				condition = trigger_condition,
				priority = priority,
			}
		)
	)

end

function tex.snip.trailing_maths_unit(str)
	not_unit_str = str:gsub("%s+$", "")
	while not_unit_str:find("%s*'$") or not_unit_str:find("%s*[_^]%b{}$") do
		not_unit_str = not_unit_str:gsub("%s*[_^]%b{}$", ""):gsub("%s*'$", "")
	end
	if not_unit_str:find("\\%w+%s*%b{}$") then
		not_unit_str = not_unit_str:gsub("\\%w+%s*%b{}$", "")
	elseif not_unit_str:find("\\%w+$") then
		not_unit_str = not_unit_str:gsub("\\%w+$", "")
	else
		not_unit_str = not_unit_str:gsub("%w$", "")
	end
	return not_unit_str, str:sub(#not_unit_str + 1)
end

function tex.snip.maths_postfix(trigger, cmd, opts)
	local postfix_fn = function (args, parent, user_args)
		local line =  parent.trigger:gsub("%s*" .. trigger .. "%s*$", "")
		local prefix, math_unit = tex.snip.trailing_maths_unit(line)
		return prefix .. cmd .. "{" .. math_unit .. "}"
	end
	tex.snip.shorthand(".+" .. trigger, f(postfix_fn), opts)
end

function tex.snip.env(envs, opts)
	local opts = opts or {}
	local pos = opts.pos or 1
	local num_args = opts.num_args or 0
	local optional_args = opts.optional_args or false
	local arg_placeholders = opts.arg_placeholders or {}
	local list = opts.list or false

	if type(envs) == "string" then
		envs = { envs }
	end

	open_envs = {}
	close_envs = {}
	for j, env in ipairs(envs) do
		table.insert(open_envs, string.rep("\t", j - 1) .. "\\begin{" .. env .. "}")
		table.insert(close_envs, 1, string.rep("\t", j - 1) .. "\\end{" .. env .. "}")
	end

	if num_args > 0 then
		return sn(pos, {
			t { unpack(open_envs) },
			optional_args and tex.snip.optional_brackets(1, num_args, arg_placeholders) or tex.snip.brackets(1, num_args, arg_placeholders),
			t { "", string.rep("\t", #envs) .. (list and "\\item " or "") }, i(2), t { "", "" },
			t { unpack(close_envs) }, t { "", "" }
			},
			{}
		)
	else
		return sn(pos, {
			t { unpack(open_envs) }, t { "",
				string.rep("\t", #envs) .. (list and "\\item " or "") }, i(1), t { "", "" }, t {
				unpack(close_envs) }, t { "" }
			},
			{}
		)
	end
end

function tex.snip.cmd(cmd, opts)
	local opts = opts or {}
	local pos = opts.pos or 1
	local num_args = opts.num_args or 0
	local optional_args = opts.optional_args or false
	local arg_placeholders = opts.arg_placeholders or {}
	return sn(pos, {
		t { cmd },
		num_args > 0 and (
			optional_args and tex.snip.optional_brackets(1, num_args, arg_placeholders)
			or tex.snip.brackets(1, num_args, arg_placeholders)
			) or nil
		},
		{}
	)
end

-----------
-- Snippets
-----------

tex.snip.shorthand("begin",
	sn(1, {
		t { "\\begin{" },
		i(1),
		t { "}", "\t" },
		i(2),
		t { "", "" }, l("\\end{" .. l._1 .. "}", 1),
	}), 
	{ starts_line = true }
)

tex.snip.shorthand("sec", tex.snip.env("section", { num_args = 1, arg_placeholders = { "title" } }), { starts_line = true })
tex.snip.shorthand("subsec", tex.snip.env("subsection", { num_args = 1, arg_placeholders = { "title" } }), { starts_line = true })
tex.snip.shorthand("ssubsec", tex.snip.env("subsubsection", { num_args = 1, arg_placeholders = { "title" } }), { starts_line = true })

tex.snip.shorthand("defn", tex.snip.env("definition", { num_args = 1, optional_args = true, arg_placeholders = { "term" } }), { starts_line = true })
tex.snip.shorthand("thm", tex.snip.env("theorem", { num_args = 1, optional_args = true, arg_placeholders = { "term" } }), { starts_line = true })
tex.snip.shorthand("prf", tex.snip.env("proof", { num_args = 1, optional_args = true, arg_placeholders = { "term" } }), { starts_line = true })
tex.snip.shorthand("tcd", tex.snip.env({ "center", "tikzcd" }), { starts_line = true })
tex.snip.shorthand("align", tex.snip.env("align"), { starts_line = true })

tex.snip.shorthand("item", tex.snip.env("itemize", { list = true }), { starts_line = true })
tex.snip.shorthand("enum", tex.snip.env("enumerate", { list = true }), { starts_line = true })
tex.snip.shorthand("desc", tex.snip.env("description", { list = true }), { starts_line = true })

tex.snip.shorthand("\tit", tex.snip.cmd("\\item"), {
	condition = function ()
		return tex.conds.in_environments { ["itemize"] = true, ["enumerate"] = true }
	end,
	starts_line = true
})
tex.snip.shorthand("\tit", tex.snip.cmd("\\item",
	{ num_args = 1, optional_args = true, arg_placeholders = { "term" }}),
	{
		condition = function ()
			return tex.conds.in_environment("description")
		end,
		starts_line = true,
	}
)

tex.snip.shorthand("epic", t "epimorphic", { not_in_maths = true })
tex.snip.shorthand("monic", t "monomorphic", { not_in_maths = true })
tex.snip.shorthand("iso", t "isomorphic", { not_in_maths = true })

-- inline maths
tex.snip.shorthand("im", tex.snip.delimiter(1, "\\( ", " \\)"), { not_in_maths = true, gobble_space = true })
tex.snip.shorthand("$", tex.snip.delimiter(1, "\\( ", " \\)"), { not_in_maths = true, gobble_space = true })

tex.snip.shorthand("_", tex.snip.cmd("_", { num_args = 1 }), { in_maths = true, in_word = true, immediate_expansion = true, gobble_space = false })
tex.snip.shorthand("%^", tex.snip.cmd("^", { num_args = 1 }), { in_maths = true, in_word = true, immediate_expansion = true, gobble_space = false })

tex.snip.maths_postfix("hat", "\\hat", { in_maths = true, in_word = true, immediate_expansion = true, gobble_space = false })
tex.snip.maths_postfix("bar", "\\overline", { in_maths = true, in_word = true, immediate_expansion = true, gobble_space = false })
tex.snip.maths_postfix("tilde", "\\widetilde", { in_maths = true, in_word = true, immediate_expansion = true, gobble_space = false })
tex.snip.maths_postfix("star", "\\star", { in_maths = true, in_word = true, immediate_expansion = true, gobble_space = false })
tex.snip.maths_postfix("op", "\\op", { in_maths = true, in_word = true, immediate_expansion = true, gobble_space = false })
-- TODO mathcal

tex.snip.shorthand("in", tex.snip.cmd("\\in"), { in_maths = true })
tex.snip.shorthand("not", tex.snip.cmd("\\not"), { in_maths = true })
tex.snip.shorthand("nin", tex.snip.cmd("\\nin"), { in_maths = true })
tex.snip.shorthand("to", tex.snip.cmd("\\to"), { in_maths = true })
tex.snip.shorthand("tto", tex.snip.cmd("\\tto"), { in_maths = true })
tex.snip.shorthand("and", tex.snip.cmd("\\And"), { in_maths = true })
tex.snip.shorthand("or", tex.snip.cmd("\\Or"), { in_maths = true })
tex.snip.shorthand("with", tex.snip.cmd("\\With"), { in_maths = true })
tex.snip.shorthand("*", tex.snip.cmd("\\times"), { in_maths = true, immediate_expansion = true })

tex.snip.shorthand("fa", tex.snip.cmd("\\ForAll", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("ex", tex.snip.cmd("\\Exists", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("nex", tex.snip.cmd("\\NExists", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("exu", tex.snip.cmd("\\ExistsUnique", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("pa", tex.snip.cmd("\\Pair", { num_args = 2 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("tr", tex.snip.cmd("\\Triple", { num_args = 3 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("quad", tex.snip.cmd("\\Quadruple", { num_args = 4 }), { ensure_maths = true, gobble_space = true })

tex.snip.shorthand("set", tex.snip.cmd("\\Set", { num_args = 1 }), { in_maths = true, gobble_space = true })
tex.snip.shorthand("hom", tex.snip.cmd("\\Hom", { num_args = 2 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("id", tex.snip.cmd("\\Id", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("ze", tex.snip.cmd("\\Zero", { num_args = 2 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("ker", tex.snip.cmd("\\Ker", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("coker", tex.snip.cmd("\\Coker", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("eq", tex.snip.cmd("\\Eq", { num_args = 2 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("coeq", tex.snip.cmd("\\Coeq", { num_args = 2 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("comma", tex.snip.cmd("\\Comma", { num_args = 2 }), { in_maths = true, gobble_space = true })

tex.snip.shorthand("sqrt", tex.snip.cmd("\\sqrt", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("sin", tex.snip.cmd("\\sin", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("cos", tex.snip.cmd("\\cos", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
tex.snip.shorthand("tan", tex.snip.cmd("\\tan", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
-- tex.snip.shorthand("csc", tex.snip.cmd("\\csc", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
-- tex.snip.shorthand("sec", tex.snip.cmd("\\sec", { num_args = 1 }), { ensure_maths = true, gobble_space = true })
-- tex.snip.shorthand("cot", tex.snip.cmd("\\cot", { num_args = 1 }), { ensure_maths = true, gobble_space = true })

-- immediate expansions
for shorthand, expansion in pairs({
	-- blackboard bold symbols
	["AA"] = "\\A", ["BB"] = "\\B", ["CC"] = "\\C", ["DD"] = "\\D", ["EE"] = "\\E", ["FF"] = "\\F", ["GG"] = "\\G", ["HH"] = "\\H", ["II"] = "\\I", ["JJ"] = "\\J", ["KK"] = "\\K", ["LL"] = "\\L", ["MM"] = "\\M", ["NN"] = "\\N", ["OO"] = "\\O", ["PP"] = "\\P", ["QQ"] = "\\Q", ["RR"] = "\\R", ["SS"] = "\\S", ["TT"] = "\\T", ["UU"] = "\\U", ["VV"] = "\\V", ["WW"] = "\\W", ["XX"] = "\\X", ["YY"] = "\\Y", ["ZZ"] = "\\Z",

	-- greek symbols
	[";a"] = "\\alpha", [";b"] = "\\beta", [";c"] = "\\chi", [";d"] = "\\delta", [";D"] = "\\Delta", [";e"] = "\\epsilon", [";f"] = "\\phi", [";F"] = "\\Phi", [";g"] = "\\gamma", [";G"] = "\\Gamma", [";h"] = "\\eta", [";i"] = "\\iota", [";k"] = "\\kappa", [";l"] = "\\lambda", [";L"] = "\\Lambda", [";m"] = "\\mu", [";n"] = "\\nu", [";o"] = "\\omega", [";O"] = "\\Omega", [";p"] = "\\pi", [";P"] = "\\Pi", [";q"] = "\\theta", [";Q"] = "\\Theta", [";r"] = "\\rho", [";s"] = "\\sigma", [";S"] = "\\Sigma", [";t"] = "\\tau", [";u"] = "\\upsilon", [";x"] = "\\xi", [";X"] = "\\Xi", [";y"] = "\\psi", [";Y"] = "\\Psi", [";z"] = "\\zeta",

	-- misc expansions
	[";\\"] = "\\emptyset",
	[";0"] = "\\0",
	[";1"] = "\\1",
	[";8"] = "\\infty",
	[";%+"] = "\\oplus",

	["=>"] = "\\implies", -- maybe move the following
	["=<"] = "\\impliedby",
	["|->"] = "\\mapsto",

	[":="] = "\\coloneqq",
	["<="] = "\\leq",
	[">="] = "\\geq",
	["~="] = "\\iso",
}) do
	tex.snip.shorthand(shorthand, tex.snip.cmd(expansion), { ensure_maths = true, in_word = true, immediate_expansion = true, gobble_space = true })
end

-- arrows in commutative diagrams
table.insert(tex.snip.autosnippets, s(
	{ trig = "a([ud]*[lr]*)(%s)", regTrig = true },
	{ l("\\ar[" .. l.CAPTURE1), tex.snip.conditional_delimiter(1, tex.conds.is_empty, { "", "" }, { ", \"", "\"" }, "label"), tex.snip.conditional_delimiter(2, tex.conds.is_empty, { "", "" }, { ", ", "" }, "modifiers"), l("]" .. l.CAPTURE2) },
	{ condition = tex.conds.in_commutative_diagram }
))

-- TODO cube in commutative diagram
-- TODO square in commutative diagram
-- TODO a_1, ..., a_n lists
-- TODO limits, sums, products
-- TODO fractions (maybe as postfix)
-- TODO cases
-- TODO tcd w/ width x height
-- TODO = in align --> &=
--

return tex.snip.snippets, tex.snip.autosnippets
