class_name LaunchOptions
## Reads the options passed after "--" on the command line:
##   --solo            start a solo game straight away
##   --server          run a dedicated server: host with no player of its own
##   --host            start hosting straight away
##   --join=ADDRESS    join ADDRESS (host, host:port or [ipv6]:port) straight away
##   --name=NAME       play as NAME instead of the saved name
##   --port=PORT       host on PORT instead of 24650
##   --seed=N          make the world from seed N (0 to 2147483647) instead of a random one
## Unknown or malformed options are ignored.


static func parse(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		if arg == "--solo":
			options["solo"] = true
		elif arg == "--host":
			options["host"] = true
		elif arg == "--server":
			options["server"] = true
		elif arg.begins_with("--join="):
			options["join"] = arg.trim_prefix("--join=")
		elif arg.begins_with("--name="):
			options["name"] = arg.trim_prefix("--name=")
		elif arg.begins_with("--port="):
			var value := arg.trim_prefix("--port=")
			if value.is_valid_int() and value.to_int() >= 1 and value.to_int() <= 65535:
				options["port"] = value.to_int()
		elif arg.begins_with("--seed="):
			var value := arg.trim_prefix("--seed=")
			if value.is_valid_int() and value.to_int() >= 0 and value.to_int() <= 0x7fffffff:
				options["seed"] = value.to_int()
	return options
