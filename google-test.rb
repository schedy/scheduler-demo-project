class InvalidTagError < StandardError; end

module SchedyHelper

	def self.parse_google_tests_list(test_package_name,options=nil)
		googletest_file_path = [SCHEDULER_SERVER_ROOT,'storage','unpacked',File.basename(test_package_name), options[:google_test_exec]].join('/')

		if !File.file?(googletest_file_path) || !File.executable?(googletest_file_path) then return [] end

		test_parse_command = [googletest_file_path, "--gtest_list_tests"].join(' ')

		puts "Parsing google tests by : #{test_parse_command}"
		parser_output = `#{test_parse_command}`

		if parser_output.blank? then return [] end

		test_cases = []
		suite_name = ""
		parser_output.each_line { |line|
			tmp = {"name": '', "tags": [], "suite": '', "steps":[]}
			if line.start_with?("  ") then
				tmp[:name] = line.strip
				tmp[:suite] = suite_name
				test_cases.push(tmp)
			else
				suite_name = line.strip
			end
		}

		if not options.nil? and options[:intersection]
			test_cases = test_cases.select { |test_case|
				(options[:intersection].include?(test_case[:name]))
			}
		end

		if not options.nil? and options[:minus]
			test_cases = test_cases.select { |test_case|
				!(options[:minus].include?(test_case[:name]))
			}
		end

		return test_cases

	end

end
