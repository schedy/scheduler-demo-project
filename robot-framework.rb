module SchedyHelper

	##INFO:
	##USED IN: scheduler-server:task_procedures/task.rb - to get list of robot tests for task creation
	def self.parse_robot_tests_list(test_package_name,options=nil)

		robot_parser_script =
			['python2 '+SCHEDULER_SERVER_ROOT,'project','creator','suite_parser.py'].join('/')

		robot_file_path =
			[SCHEDULER_SERVER_ROOT,'storage','unpacked',File.basename(test_package_name)].join('/')

		test_parse_command = [robot_parser_script,robot_file_path].join(' ')

		puts "Parsing robot tests by : #{test_parse_command}"
		parser_output = `#{test_parse_command}`

		if parser_output.blank? then return [] end

		test_suite_json = JSON.parse(parser_output)

		if not options.nil? and not options[:intersection].nil? and options[:intersection].is_a?(Array) and options[:intersection].join.length > 0
			test_suite_json = test_suite_json.select { |test_case|
				!(test_case["tags"].grep Regexp.union(options[:intersection])).empty? }
				#!(test_case["tags"] & options[:intersection]).empty? }
		end

		if not options.nil? and not options[:minus].nil? and options[:minus].join.length > 0
			test_suite_json = test_suite_json.select { |test_case|
				(test_case["tags"] & options[:minus]).empty? }
		end

		if not options.nil? and not options[:select_name].nil? and options[:select_name].join.length > 0
			test_suite_json = test_suite_json.select { |test_case|
				(test_case["name"].match(/#{Regexp.new(options[:select_name].join)}/)) }
		end

		test_suite_json

	end




	def self.parse_ci_tag(tag)

		parsed_tag_string = tag.strip.match(/(.*){(.*)}/)
		operators = [':','->','<-']
		if (parsed_tag_string.nil? or parsed_tag_string.size < 3) then raise InvalidTagError end
		edge_tag_atoms = parsed_tag_string[2].strip.gsub(/(?<!\\)->|(?<!\\)<-/) { |match| " #{match} " }.split(' ').map(&:strip)
		mem = []

		vertices = edge_tag_atoms.map.with_index { |atom,i|
			if operators.include?(atom) then next end
			vertex = {}
			keys = [:label,:type]
			values = atom.split(/(?<!\\):/)
			values.zip(keys) {|a,b|
				if !mem.select{ |e| e[:label]==values[0]  }.empty?
					#raise InvalidTagError
					next
				end

				if (b.nil? and !a.empty?)
					vertex[a.split('=').first.to_sym]= a.split('=').last
				else
					vertex[b] = a
				end
			}
			mem << vertex
			vertex
		}.compact.reject(&:empty?)

		operator_indices = edge_tag_atoms.each_index.select { |i| operators.include?(edge_tag_atoms[i]) }
		edges = operator_indices.map { |i|
			if (edge_tag_atoms[i].to_s.empty? || edge_tag_atoms[i-1].to_s.empty? || edge_tag_atoms[i+1].to_s.empty?) then failed=true; next end
			case edge_tag_atoms[i]
			when '->'
				{from: edge_tag_atoms[i-1].split(/(?<!\\):/)[0], to: edge_tag_atoms[i+1].split(/(?<!\\):/)[0], is_edge: true}
			when '<-'
				{from: edge_tag_atoms[i+1].split(/(?<!\\):/)[0], to: edge_tag_atoms[i-1].split(/(?<!\\):/)[0], is_edge: true}
			end
		}.compact.reject(&:empty?)

		edges.map { |edge| if (edge[:from].nil? or edge[:to].nil?) then raise InvalidTagError end }

		vertices.map { |vertex| if (vertex[:type].nil? and vertex[:label].nil?) then next end}

		(vertices+edges).compact

	end


	def self.ci_tag_to_graphmatcher(requirement_tags)
		vertices = requirement_tags.select { |a| !a[:is_edge] }.map { |atom|
			atom[:children_ids] = []
			atom
		}
		edges = requirement_tags.select { |a| a[:is_edge] }.map { |atom|
			f_vertex = vertices.find { |v| v[:label] == atom[:from] }
			f_index = vertices.index(f_vertex)
			t_vertex = vertices.find { |v| v[:label] == atom[:to] }
			t_index = vertices.index(t_vertex)
			vertices[f_index][:children_ids] << t_index
		}
		vertices
	end


	def self.parse_robot_test_tags(robot_test)
		result = {}
		tags = robot_test["tags"]
		tags.map { |tag|
			parsed_tag_string =  if tag.start_with?('SSyRS') or tag.start_with?('DD')
									 tag.strip.match(/(.*)_(.*)/) or next
								 elsif tag.strip.match(/(.*){(.*)}/)
									 tag.strip.match(/(.*){(.*)}/) or next
								 else
									 [tag.strip,tag.strip,tag.strip]
								 end
			raw_tag = parsed_tag_string[0].strip
			tag_type = parsed_tag_string[1].strip
			tag_content = parsed_tag_string[2].strip
			result[tag_type] = { header: tag_type, content: tag_content, raw: raw_tag }
		}
		result
	end


end
