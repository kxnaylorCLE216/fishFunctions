function cat

	if not test -f $argv
		echo "File not found: $argv"
		return 0
	end

	command bat $argv
end
