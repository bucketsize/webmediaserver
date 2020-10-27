--[[
export LUA_PATH='/home/jb/.luarocks/share/lua/5.3/?.lua;/home/jb/lib/?.lua'
export LUA_CPATH='/home/jb/.luarocks/lib/lua/5.3/?.so'
--]]

local Util = require('util')

local restserver = require("restserver")
local lfs = require"lfs"

local server = restserver:new():port(8083)
local hls_url = 'http://fuhrer-fu:8081/hls'
local media_base_path = '/mnt/f1aa/var/webmedia/root/'


function file_exists(file)
	local h = io.open(file, "r")
	if h == nil then
		return false
	end
	h:close()
	return true
end
function exec(cmd)
	local h = io.popen(cmd)
	local r
	if h == nil then
		r = ""
	else
		r = h:read("*a")
		h:close()
	end
	return r
end
function gen_thumbnail(file)
	print('gen_thumbnail: '..file)
	local thm = file..'.png'
	if file_exists(thm) then
		return
	end
	local cmd = string.format('ffmpegthumbnailer -mf -i %s -o %s', file, thm)
	exec(cmd)
end
local _M = {
	fs = {},
	loaded = false
}
function list_files(page, page_size)
	if not _M.loaded then
		Util:stream_file('/var/tmp/video.playlist', function(l)
			local ds = Util:split(l, Util.PSV_PAT)
			table.insert(_M.fs, ds[1])
		end)
		_M.loaded = true
	end
	if page == nil then page = 1 end
	if page_size == nil then page_size = 5 end
	local i = (page-1)*page_size+1
	local j = page*page_size
	local fs = {}
	for ii=i,j,1 do
		local item = _M.fs[ii]
		if item == nil then break end
		table.insert(fs, item)
	end
	return fs
end
function list_files_from_dir(path, dir, files, attrs)
	for file in lfs.dir(path) do
		print(file)
		if file ~= "." and file ~= ".." then
			local f = path..'/'..file
			local fr = dir..'/'..file
			if string.find(file, "mp4") ~= nil
				and string.find(file, "png") == nil then
				print ("\t "..fr)
				gen_thumbnail(f)
				table.insert(files, fr)
			end
			local attr = lfs.attributes (f)
			assert (type(attr) == "table")
			if attr.mode == "directory" then
				list_files_from_dir(f, dir..'/'..file, files, attrs)
			else
				attrs[file] = attr
			end
		end
	end
end
server:add_resource("files", {
		{
			method = "GET",
			path = "/",
			produces = "application/json",
			handler = function()
				local testdir = "/opt"
				local files = {}
				local attrs = {}
				list_files(testdir, "", files, attrs)
				return restserver.response():status(200):entity({files=files, attrs=attrs})
			end,
		},
	})
server:add_resource("static", {
		{
			method = "GET",
			path = '{file:.*}',
			produces = "",
			handler = function(params, file)
				print('GET '..file)
				local fstr = Util:read('static/'..file)
				if fstr == nil then
					print('404 '..file)
					return restserver.response()
						:status(404)
						:entity("404::Not Found")
				end
				local headers = {}
				headers['Access-Control-Allow-Origin'] = '*'
				return restserver.response()
					:status(200)
					:entity(fstr)
			end,
		},
	})
server:add_resource("playlist", {
		{
			method = "GET",
			path = '/',
			produces = "application/json",
			handler = function(params)
				local page=params.page
				local page_size=params.page_size
				local files = list_files(page, page_size)
				local playl = {}
				for i,f in ipairs(files) do
					local ff = string.gsub(f, ' ', '\\ ')
					local icon_file = media_base_path..ff
					gen_thumbnail(icon_file)
					table.insert(playl, {
							url = string.format('%s/%s', hls_url, f),
							image = string.format('%s/%s.png', hls_url, f),
							name = string.match(f, '/([%a%d%s+=-_\\.\\]*)$')
						})
				end

				local headers = {page = page, page_size = page_size}
				headers['Access-Control-Allow-Origin'] = '*'
				return restserver.response()
					:status(200)
					:headers(headers)
					:entity(playl)
			end,
		},
	})
server:add_resource("playlist_dir", {
		{
			method = "GET",
			path = "/",
			produces = "application/json",
			handler = function()
				local mdirs = {
					"/mnt/f1aa/var/webmedia/root/",
				}
				local files = {}
				local attrs = {}
				for i,d in ipairs(mdirs) do
					list_files(d, "", files, attrs)
				end
				local playl = {}
				for i,f in ipairs(files) do
					table.insert(playl, {
							url = string.format('%s/%s', hls_url, f),
							image = string.format('%s/%s.png', hls_url, f)
						})
				end

				local headers = {}
				headers['Access-Control-Allow-Origin'] = '*'
				return restserver.response()
					:status(200)
					:headers(headers)
					:entity(playl)
			end,
		},
	})

server:set_error_handler({
		produces = "application/json",
		handler = function(code, msg)
			return {
				code = code,
				message = msg,
			}
		end,
	})

server.server_name = "webmedia-dsc"

function test_list_files()
	print('-- page', 1)
	Util:printTable(list_files())

	print('-- page', 2)
	Util:printTable(list_files(2, 5))
	
	print('-- page', 3)
	Util:printTable(list_files(3, 5))
	
	print('-- page', 500)
	Util:printTable(list_files(500, 5))
end

-- test_list_files()

server:enable("restserver.xavante"):start()
