require 'find' #for Find.find
require 'erb'

module SchedyHelper


	##INFO:
	##USED IN: scheduler-server/project/creator/task_procedures/task.rb - to generate tasks according to package config
	def self.generate_tasks(options)
		self.send("generate_tasks_for_"+(options[:test_package_config]["executor"].first or ["python-robot.rb"].first).gsub(/(^[^a-zA-Z])|[^a-zA-z]/s,"_"), options)
	end



	def self.generate_tasks_for_python_robot_rb(options)
		test_package_name = options[:test_package_name]
		test_package_config = options[:test_package_config]
		package_name = options[:package_name]
		description = options[:description]
		extracted_required_packages = options[:extracted_required_packages]
		obs = options[:obs]
		#empty execution if not test_environment should we have a default test_environment
		(test_package_config["test-environments"] or {}).map { |test_environment_name,test_environment_content|

			test_package_uris=[]
			robot_tests_list=[]

			#tags_intersect = (test_package_config["test-environments"][test_environment_name]["tags-intersect"])

			tags_intersect = (test_package_config["test-environments"][test_environment_name]["tags-intersect"])

			tags_reject = (test_package_config["test-environments"][test_environment_name]["tags-reject"])

			if description.target_tag and description.target_tag.size > 0
				tags_intersect ||= []
				tags_intersect += description.target_tag
			end
			package = obs.package(project: description.package_project[package_name], repo: test_package_config["repo"], arch: test_package_config["arch"],  package_name: package_name)
			package.binaries.map { |binary|
				next if binary.name  !~ /#{test_package_name}/
				downloaded_config_package_path = binary.download(target_directory: SCHEDULER_SERVER_ROOT+'/storage/rpms')
				extracted_package_path = Archive.extract(archive_path: downloaded_config_package_path, target_directory: SCHEDULER_SERVER_ROOT+'/storage/unpacked', set_read_only: true)
				robot_tests_list << (
					SchedyHelper.parse_robot_tests_list(extracted_package_path,{:intersection => tags_intersect,:minus => tags_reject, :test_environment => test_environment_name, :select_name => description.target_name}).each { |test|
						test["origin"] = [SCHEDULER_URI, 'storage', 'rpms', File.basename(extracted_package_path).to_s].join('/')
					}
				)
			}

			robot_tests_list.flatten!


			robot_tests_list.map do |robot_test|
				hooks = robot_test['hooks'] || nil
				tags = { name: [robot_test['name']] }

				parsed_tags = SchedyHelper.parse_robot_test_tags(robot_test)

				ci_tag = parsed_tags["#{test_environment_name}"] ? parsed_tags["#{test_environment_name}"][:raw] : ''
				next if ci_tag.blank?

				dd_tags = parsed_tags['DD'] ? parsed_tags['DD'][:content] : ''
				if not dd_tags.blank? then tags[:dd_tags] = dd_tags.split(' ') end

				ssyrs_tags = parsed_tags['SSyRS'] ? parsed_tags['SSyRS'][:content] : ''
				if not ssyrs_tags.blank? then tags[:ssyrs] = ssyrs_tags.split(' ') end

				trace_tags = parsed_tags['TRACE'] ? parsed_tags['TRACE'][:content] : ''
				if not trace_tags.blank?
					tags[:trace] = []
					trace_tags.split(' ').map { |trace_tag|
						if trace_tag.include?(':') then
							split_trace_tag = trace_tag.split(':')
							key=split_trace_tag[0]
							value=split_trace_tag[1]
							if key==test_environment_name then tags[:trace] << value end
						else
							tags[:trace] << trace_tag
						end
					}
					#tags[:trace] = trace_tags.split(' ')


				end

				if test_environment_name then tags[:environment] = [test_environment_name] end

				if not test_package_config["gating_tag"].blank? and parsed_tags.keys.find { |t| t.to_s =~ /#{test_package_config["gating_tag"]}/} then tags[:gating_tag] = [parsed_tags.keys.find { |t| t.to_s =~ /#{test_package_config["gating_tag"]}/}] end
				#if not test_package_config["gating_tag"].blank? and parsed_tags[test_package_config["gating_tag"]] then tags[:gating_tag] = [test_package_config["gating_tag"]] end

				timeout_duration = if parsed_tags['TIMEOUT']
									   parsed_tags['TIMEOUT'][:content]
								   elsif test_package_config["timeout"].length > 0
									   test_package_config["timeout"]
								   else
									   '1800'
								   end
				if test_environment_name == "RESPIRATION_INTEGRATED_MAIN" then debug=true end
				parsed_ci_tag = SchedyHelper.parse_ci_tag(ci_tag)

				graphmatcher_requirements = SchedyHelper.ci_tag_to_graphmatcher(parsed_ci_tag)

				graphmatcher_requirements.each { |req_tag|

					((test_package_config["test-environments"][test_environment_name]["default-role-options"] or {})[req_tag[:label]] or {}).each {|k,v|
						unless req_tag.has_key?(k)
							req_tag[k]=v
						end
					}
				}


				prepared_requirements = graphmatcher_requirements.map do |req_tag|
					flashables=(req_tag["flashables"] or "").split(',')
					if debug then p ['DEBUG:',flashables].join end
					toflash = {}
					##set toflash
                                        if debug then p ['DEBUG:',extracted_required_packages].join end
					flashables.uniq.each { |flashable|
						binarypath = extracted_required_packages.flatten.find { |e|
							flashable_regexp = req_tag["#{flashable}-package"]
							e.match(/#{flashable_regexp}/)
						}
						if debug then p ['DEBUG:',binarypath].join end

						#binarypath split is dirty
						if binarypath

							remote_uri = [SCHEDULER_URI, 'storage', 'rpms', File.basename(binarypath).to_s].join('/')

							image_path = SchedyHelper.locate_target(archive: binarypath , regexp: req_tag[flashable+'-image'])

							flasher_path = if req_tag[flashable+'-flasher'] then SchedyHelper.locate_target(archive: binarypath , regexp: req_tag[flashable+'-flasher']) else '' end

							if image_path
								toflash[flashable] =  {
									package: remote_uri,
									path: image_path,
									flasher: flasher_path
								}
							end

						end
					}
					##
					{
						children: req_tag[:children_ids],
						type: req_tag[:type],
						images: toflash,
						options: req_tag["options"],
						role: req_tag[:label],
						flash_script: test_package_config["flash_script"]
					}.merge(req_tag.reject { |k,v| [:label, :type, :children_ids].include?(k) })
				end

				{
					required_repos: options[:required_repos],
					required_packages: options[:required_packages],
					requirements: prepared_requirements,
					test_name: robot_test['name'],
					duration_key: [robot_test['name'],test_environment_name.to_s],
					tags: tags,
					hooks: hooks,
					has_resource_groups: test_package_config["has-resource-groups"],
					target_resources: description["target_resources"],
					test_environment: test_environment_name.to_s,
					test_package: robot_test['origin'],
					command_line: test_package_config["command-line"].join(' '),
					environment_variables: test_package_config["environment-vars"].join(' '),
					timeout: timeout_duration,
					executor: ['executor.rb'],
					priority: test_package_config["priority"]
				}
			end
		}
	end

	def self.generate_tasks_for_generic_rb(options)
		test_package_name = options[:test_package_name]
		test_package_config = options[:test_package_config]
		package_name = options[:package_name]
		description = options[:description]
		extracted_required_packages = options[:extracted_required_packages]

		#empty execution if not test_environment should we have a default test_environment
		(test_package_config["test-environments"] or {}).map { |test_environment_name,test_environment_content|
			test_package_uris=[]
			generic_tests_list=[]

			testcases_intersect = (test_package_config["testcases-intersect"])
			testcases_reject = (test_package_config["testcases-reject"])
			generic_test_exec = (test_package_config["generic-test-exec"])

			if description.target_tag and description.target_tag.size > 0
				testcases_intersect ||= []
				testcases_intersect += description.target_tag
			end

			generic_tests_list = test_package_config["test-list"]
			generic_test_hooks = test_package_config["hooks"] || nil
			generic_tests_list.map { |generic_test|

				#hooks = generic_test['hooks'] || nil
				hooks = if generic_test_hooks.size > 0 and generic_test['suite']
					generic_test_hooks[generic_test['suite']]
				else
					nil
				end

				tags = { name: [generic_test['name']], suite: [generic_test['suite']] }

				test_environment_configuration = generic_test['configuration'] || (test_package_config["test-environments"][test_environment_name]["configuration"])

				if test_environment_name then tags[:environment] = [test_environment_name] end

				timeout_duration = if generic_test["timeout"] and generic_test["timeout"].length > 0
									   generic_test["timeout"]
								   else
									   '18000'
								   end

				next if test_environment_configuration.blank?

				parsed_ci_tag = SchedyHelper.parse_ci_tag(test_environment_configuration)

				graphmatcher_requirements = SchedyHelper.ci_tag_to_graphmatcher(parsed_ci_tag)

				graphmatcher_requirements.each { |req_tag|
					((test_package_config["test-environments"][test_environment_name]["default-role-options"] or {})[req_tag[:label]] or {}).each {|k,v|
						unless req_tag.has_key?(k)
							req_tag[k]=v
						end
					}
				}
				recipe_info = {}
				test_environment_data = test_package_config["test-environments"][test_environment_name]

				recipes = (test_environment_data["recipes"] or "").split(",")

				recipes.uniq.each { |recipe|
					p "Discovered recipe ! #{recipe}"
					package = extracted_required_packages.flatten.find { |e|
						recipe_package_regexp = test_environment_data["#{recipe}-package"]
						p "Regexp for recipe package #{recipe_package_regexp}"
						e.match(/#{recipe_package_regexp}/)
					}
					p "Package for recipe: #{package}"

					if package
						package_uri = [SCHEDULER_URI, 'storage', 'rpms', File.basename(package).to_s].join('/')
						recipe_path = SchedyHelper.locate_target(archive: package , regexp: test_environment_data["#{recipe}-file"])
						p "Regexp for the recipe :"+test_environment_data["#{recipe}-file"]
						p "Recipe found at @ #{recipe_path}"
						if recipe_path
							recipe_info[recipe] = {
								package: package_uri,
								path: recipe_path
							}
						end
						p "Recipe info : #{recipe_info.to_s}"
					end
				}#recipes.uniq.each

				prepared_requirements = graphmatcher_requirements.map { |req_tag|
					flashables=(req_tag["flashables"] or "").split(',')
					toflash = {}

					flashables.uniq.each { |flashable|
						binarypath = extracted_required_packages.flatten.find { |e|
							flashable_regexp = req_tag["#{flashable}-package"]
							e.match(/#{flashable_regexp}/)
						}
						#binarypath split is dirty
						if binarypath
							remote_uri = [SCHEDULER_URI, 'storage', 'rpms', File.basename(binarypath).to_s].join('/')
							image_path = SchedyHelper.locate_target(archive: binarypath , regexp: req_tag[flashable+'-image'])
							flasher_path = if req_tag[flashable+'-flasher'] then SchedyHelper.locate_target(archive: binarypath , regexp: req_tag[flashable+'-flasher']) else '' end
							if image_path
								toflash[flashable] =  {
									package: remote_uri,
									path: image_path,
									flasher: flasher_path
								}
							end
						end
					} # flashables.uniq.each

					{
						children: req_tag[:children_ids],
						type: req_tag[:type],
						images: toflash,
						options: req_tag["options"],
						role: req_tag[:label],
						flash_script: test_package_config["flash_script"]
					}.merge(req_tag.reject { |k,v| [:label, :type, :children_ids].include?(k) })
				} # prepared_requirements
				{
					required_repos: options[:required_repos],
					required_packages: options[:required_packages],
					recipes: recipe_info,
					requirements: prepared_requirements,
					test_name: generic_test['name'],
					duration_key: [generic_test['suite'], generic_test['name'],test_environment_name.to_s],
					tags: tags,
					hooks: hooks,
					generic_task_info: generic_test,
					has_resource_groups: test_package_config["has-resource-groups"],
					target_resources: description["target_resources"],
					test_environment: test_environment_name.to_s,
					command_line: test_package_config["command-line"].join(' '),
					environment_variables: test_package_config["environment-vars"].join(' '),
					timeout: timeout_duration,
					executor: test_package_config["executor"],
					priority: test_package_config["priority"]
				}
			}
		}
	end

	def self.generate_tasks_for_googletest_rb(options)
		test_package_name = options[:test_package_name]
		test_package_config = options[:test_package_config]
		package_name = options[:package_name]
		description = options[:description]
		extracted_required_packages = options[:extracted_required_packages]

		#empty execution if not test_environment should we have a default test_environment
		(test_package_config["test-environments"] or {}).map { |test_environment_name,test_environment_content|
			test_package_uris=[]
			google_tests_list=[]

			testcases_intersect = (test_package_config["testcases-intersect"])
			testcases_reject = (test_package_config["testcases-reject"])
			google_test_exec = (test_package_config["google-test-exec"])
			test_environment_configuration = (test_package_config["test-environments"][test_environment_name]["configuration"])

			if description.target_tag and description.target_tag.size > 0
				testcases_intersect ||= []
				testcases_intersect += description.target_tag
			end

			if false
				SchedyHelper.fetch_binary_packages_from_obs(
					SCHEDULER_SERVER_ROOT,
					description.package_project[package_name],
					test_package_config["repo"],
					test_package_config["arch"],
					package_name,
					/#{test_package_name}/).each { |test_package|
					SchedyHelper.process_obs_archive(SCHEDULER_SERVER_ROOT, test_package)
					google_tests_list << (
						SchedyHelper.parse_google_tests_list(test_package,{
																 :intersection => testcases_intersect,
																 :minus => testcases_reject,
																 :test_environment => test_environment_name,
																 :google_test_exec => google_test_exec }).each { |test|
							test["origin"] = [SCHEDULER_URI, 'storage', 'rpms', File.basename(test_package).to_s].join('/')
						}
					)
					google_tests_list.flatten!
				}
			end
			google_tests_list = {}
			google_tests_list.map { |google_test|

				tags = {name: [google_test[:name]]}

				if test_environment_name then tags[:environment] = [test_environment_name] end

				timeout_duration = if test_package_config["timeout"].length > 0
									   test_package_config["timeout"]
								   else
									   '1800'
								   end

				next if test_environment_configuration.blank?
				parsed_ci_tag = SchedyHelper.parse_ci_tag(test_environment_configuration)

				graphmatcher_requirements = SchedyHelper.ci_tag_to_graphmatcher(parsed_ci_tag)

				graphmatcher_requirements.each { |req_tag|
					((test_package_config["test-environments"][test_environment_name]["default-role-options"] or {})[req_tag[:label]] or {}).each {|k,v|
						unless req_tag.has_key?(k)
							req_tag[k]=v
						end
					}
				}


				prepared_requirements = graphmatcher_requirements.map { |req_tag|
					flashables=(req_tag["flashables"] or "").split(',')
					toflash = {}

					flashables.uniq.each { |flashable|
						binarypath = extracted_required_packages.flatten.find { |e|
							flashable_regexp = req_tag["#{flashable}-package"]
							e.match(/#{flashable_regexp}/)
						}
						#binarypath split is dirty
						if binarypath
							remote_uri = [SCHEDULER_URI, 'storage', 'rpms', File.basename(binarypath).to_s].join('/')
							image_path = SchedyHelper.locate_target(archive: binarypath , regexp: req_tag[flashable+'-image'])
							flasher_path = if req_tag[flashable+'-flasher'] then SchedyHelper.locate_target(archive: binarypath , regexp: req_tag[flashable+'-flasher']) else '' end
							if image_path
								toflash[flashable] =  {
									package: remote_uri,
									path: image_path,
									flasher: flasher_path
								}
							end
						end
					} # flashables.uniq.each

					{
						children: req_tag[:children_ids],
						type: req_tag[:type],
						images: toflash,
						options: req_tag["options"],
						role: req_tag[:label],
						flash_script: test_package_config["flash_script"]
					}.merge(req_tag.reject { |k,v| [:label, :type, :children_ids].include?(k) })
				} # prepared_requirements

				{
					requirements: prepared_requirements,
					test_name: "#{google_test[:suite]}#{google_test[:name]}",
					duration_key: [google_test[:suite], google_test[:name],test_environment_name.to_s],
					tags: tags,
					has_resource_groups: test_package_config["has-resource-groups"],
					target_resources: description["target_resources"],
					test_environment: test_environment_name.to_s,
					test_package: google_test['origin'],
					command_line: test_package_config["command-line"].join(' '),
					environment_variables: test_package_config["environment-vars"].join(' '),
					timeout: timeout_duration,
					executor: ['googletest.rb'],
					priority: test_package_config["priority"]
				}
			}
		}
	end

	def self.generate_tasks_for_mechatouch_rb(options)
		test_package_name = options[:test_package_name]
		test_package_config = options[:test_package_config]
		package_name = options[:package_name]
		description = options[:description]
		extracted_required_packages = options[:extracted_required_packages]

		binarypath = extracted_required_packages.flatten.find { |e|
			e.to_s.match(/dut-.*\.zip/)
		}

		ipkpath = extracted_required_packages.flatten.find { |e| e.to_s.match(/dut_(.*)imx7d/) }.to_s

		mfg_image_path = [SCHEDULER_URI, 'storage', 'rpms', File.basename(binarypath).to_s].join('/')
		ipk_path = [SCHEDULER_URI, 'storage', 'rpms', File.basename(ipkpath).to_s].join('/')


		#empty execution if not test_environment should we have a default test_environment
		(test_package_config["test-environments"] or {}).map { |test_environment_name,test_environment_content|
			mechatouch_branch = ERB.new(test_package_config["branch"]).result(binding) #test_package_config["branch"]
			mechatouch_tag = ERB.new(test_package_config["select-tag"]).result(binding) #test_package_config["select-tag"]
			if not Net::HTTP.get_response(URI(MECHATOUCH_URL+"/branches/name:"+mechatouch_branch+"/scenarios.json")).code.to_s == "200" then mechatouch_branch = test_package_config["default-branch"] end
			scenarios = JSON.parse(Net::HTTP.get(URI(MECHATOUCH_URL+"/branches/name:"+mechatouch_branch+"/scenarios.json?tag="+mechatouch_tag)))

			scenarios.map { |scenario|
				tags = { name: [scenario['reference']]}


				prepared_requirements =  [{
											  type: 'DUT',
											  images: {
												  mfgimage: {
													  package: mfg_image_path,
													  path: File.basename(mfg_image_path)
												  },
												  ipk: {
													  package: ipk_path,
													  path: File.basename(ipk_path)
												  }
											  },
											  children: [],
											  role: 'dut'
										  }]

				{
					requirements: prepared_requirements,
					test_name: scenario['reference'],
					duration_key: [scenario['reference'],test_environment_name.to_s],
					scenario_uuid: scenario['uuid'],
					tags: tags,
					test_environment: test_environment_name.to_s,
					branch: test_package_config["branch"],
					timeout: "1800",
					executor: ['mechatouch.rb', 'master', scenario['uuid']],
					priority: test_package_config["priority"]
				}
			}
		}
	end



	##INFO:
	##USED IN: scheduler-server/project/creator/task_procedures/task.rb - to locate a binary to test in a package.
	def self.locate_target(regexp: , archive:)
		if !regexp then return nil end
		package_dir = SCHEDULER_SERVER_ROOT+'/storage/unpacked/'+File.basename(archive)
		puts ['locating target for..',regexp, archive, package_dir].join(' ')

		return File.basename(archive) if archive =~ %r[#{regexp.delete('/')}]

		image_path = Find.find(package_dir).find{ |e| if !FileTest.directory?(e) then (e =~ /hex|bin|zip|ipk|vmdk|whl|ovf|py|sh|swu|dockerfile/) && (e =~ %r[#{regexp.delete('/')}]) end }

		if image_path
			image_path[package_dir.size..-1]
		else
			puts "Folder does not include flashable image: #{archive}"
		end

	end
end
