require_relative './config.rb'
require 'awesome_print'
require 'active_support/core_ext/hash'
require 'find'
require 'fileutils'

class NotOnOBS < Exception; end
class SoftFail < Exception; end
class RequestUnsuccessful < SoftFail; end
class FlashingError < Exception; end
class FatalFlashingError < Exception; end
class CorruptPackageError < StandardError; end
class FlashingError; end
class InvalidTagError < StandardError; end


module SchedyHelper

	##INFO: fetch_package uses it for creating a directory lock.
	##USED IN: helpers.rb
	def self.lockdir(lockname)
		begin
			Dir.mkdir(lockname)
			puts ['Lockdir created : ',lockname].join(' ')
		rescue Errno::EEXIST
			sleep(1)
			retry
		end
		return_value = yield
		Dir.rmdir(lockname)
		puts ['Lockdir removed : ',lockname].join(' ')
		return_value
	rescue SoftFail
		Dir.rmdir(lockname)
		puts ['Lockdir removed : ',lockname].join(' ')
		raise
	end

	##INFO:
	##USED IN: scheduler-worker:executor.rb - used for unpacking packages to worker storage
	def self.extract_to_worker_storage(package_path)

		SchedyHelper.lockdir(package_path+'_EXTRACT_LOCK') {
			# INFO: Remember to chdir back to task directory.
			task_dir = Dir.pwd

			# INFO: Get name of downloaded package for directory name.
			package_name = File.basename(package_path)

			# INFO: Get extension of the downloaded package.
			package_extension = File.extname(package_path)

			prepared_local_unpack_directory = [SCHEDULER_WORKER_ROOT,'storage','unpacked',package_name].join('/')
			next prepared_local_unpack_directory if File.directory?(prepared_local_unpack_directory)

			case package_extension

			when ".rpm"

				# INFO: Validate package content.
				SchedyHelper.validate_package(package_path)

				FileUtils::mkdir_p(prepared_local_unpack_directory)
				Dir.chdir(prepared_local_unpack_directory)

				# INFO: Extract rpm package to current directory using silenced cpio.
				puts 'Extracting RPM to '+prepared_local_unpack_directory
				extract_command = ['rpm2cpio',package_path,'|','cpio','-ivd','2>','/dev/null'].join(' ')
				p extract_command
				`#{extract_command}`
				# INFO: You can only watch, don't touch.
				begin
					FileUtils.chmod_R("ugo-w",FileUtils.pwd())
					puts "chmod -w successful !"
				rescue
					raise "chmod -w failed ! broken permissions in rpm folder !"
				end
			when ".zip"

				FileUtils::mkdir_p(prepared_local_unpack_directory)
				Dir.chdir(prepared_local_unpack_directory)

				# INFO: Extract rpm package to current directory using silenced cpio.
				puts 'Extracting ZIP to '+prepared_local_unpack_directory
				extract_command = ['unzip',package_path].join(' ')
				p extract_command
				`#{extract_command}`
				# INFO: You can only watch, don't touch.
				begin
					FileUtils.chmod_R("ugo-w",FileUtils.pwd())
					puts "chmod -w successful !"
				rescue
					raise "chmod -w failed ! broken permissions in rpm folder !"
				end

			end
			# INFO: Go back to task directory
			Dir.chdir(task_dir)
			next prepared_local_unpack_directory
		}
	end

	##INFO:
	##USED IN: scheduler-server:task_procedures/task.rb - after fetch, to extract/copy incoming packages ::
	def self.process_obs_archive(destination_directory, package_name)
		p ["process_obs_archive","dest",destination_directory,"packname",package_name].join(' ')
		unpacked_directory = destination_directory+'/storage/unpacked/'+File.basename(package_name)
		p "Target unpack directory: #{unpacked_directory}"
		return unpacked_directory if Dir.exists?(unpacked_directory)
		extension = File.extname(package_name)
		extract_command = nil
		case extension
		when '.rpm'
			p ["#{extension}: Working directory is:",Dir.pwd,'Target package name is:',package_name,'Extracting..'].join(' ')
			extract_command = ['(','mkdir','-p',unpacked_directory,'&&','cd',unpacked_directory,'&&','rpm2cpio',package_name,'|','cpio','-ivd','2>','/dev/null)'].join(' ')
		when '.zip'
			p ["#{extension}: Working directory is:",Dir.pwd,'Target package name is:',package_name,'Extracting..'].join(' ')
			extract_command = ['(','mkdir','-p',unpacked_directory,'&&','cd',unpacked_directory,'&&','unzip',package_name,")"].join(' ')
		else
			puts "cannot identify #{extension}, don't do anything..."
			extract_command = ['mkdir','-p',unpacked_directory].join(' ')
		end
		p `#{extract_command}`
		return unpacked_directory
	end



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
		#empty execution if not test_environment should we have a default test_environment
		(test_package_config["test-environments"] or {}).map { |test_environment_name,test_environment_content|

			test_package_uris=[]
			robot_tests_list=[]

			tags_intersect = (test_package_config["test-environments"][test_environment_name]["tags-intersect"])
			tags_reject = (test_package_config["test-environments"][test_environment_name]["tags-reject"])

			if description.target_tag and description.target_tag.size > 0
				tags_intersect ||= []
				tags_intersect += description.target_tag
			end

			SchedyHelper.fetch_binary_packages_from_obs(
				SCHEDULER_SERVER_ROOT,
				description.package_project[package_name],
				test_package_config["repo"],
				test_package_config["arch"],
				package_name,
				/#{test_package_name}/).each { |test_package|

				SchedyHelper.process_obs_archive(SCHEDULER_SERVER_ROOT, test_package)

				robot_tests_list << (
					SchedyHelper.parse_robot_tests_list(test_package,{:intersection => tags_intersect,:minus => tags_reject, :test_environment => test_environment_name}).each { |test|
						test["origin"] = [SCHEDULER_URI, 'storage', 'rpms', test_package.split('/')[-2], File.basename(test_package).to_s].join('/')
					}
				)
				robot_tests_list.flatten!

			}


			robot_tests_list.map do |robot_test|

				tags = { name: [robot_test['name']] }

				parsed_tags = SchedyHelper.parse_robot_test_tags(robot_test)

				ci_tag = parsed_tags["#{test_environment_name}"] ? parsed_tags["#{test_environment_name}"][:raw] : ''
				next if ci_tag.blank?

				if test_environment_name then tags[:environment] = [test_environment_name] end

				if not test_package_config["gating_tag"].blank? and parsed_tags[test_package_config["gating_tag"]] then tags[:gating_tag] = [test_package_config["gating_tag"]] end

				timeout_duration = if parsed_tags['TIMEOUT']
									   parsed_tags['TIMEOUT'][:content]
								   elsif test_package_config["timeout"].length > 0
									   test_package_config["timeout"]
								   else
									   '1800'
								   end

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

					toflash = {}
					##set toflash

					flashables.uniq.each { |flashable|
						binarypath = extracted_required_packages.flatten.find { |e|
							flashable_regexp = req_tag["#{flashable}-package"]
							e.match(/#{flashable_regexp}/)
						}
						#binarypath split is dirty
						if binarypath

							remote_uri = [SCHEDULER_URI, 'storage', 'rpms', binarypath.split('/')[-2], File.basename(binarypath).to_s].join('/')

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
					requirements: prepared_requirements,
					test_name: robot_test['name'],
					duration_key: [robot_test['name'],test_environment_name.to_s],
					tags: tags,
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
								test["origin"] = [SCHEDULER_URI, 'storage', 'rpms', test_package.split('/')[-2], File.basename(test_package).to_s].join('/')
						}
					)
					google_tests_list.flatten!
				}

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
							remote_uri = [SCHEDULER_URI, 'storage', 'rpms', binarypath.split('/')[-2], File.basename(binarypath).to_s].join('/')
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

		device_image_path = nil

		binarypath = extracted_required_packages.flatten.find { |e|
			e.match(/device-image/)
		}

		SchedyHelper.process_obs_archive(SCHEDULER_SERVER_ROOT, binarypath)
		device_image_path = [SCHEDULER_URI, 'storage', 'rpms', 'device-image', File.basename(binarypath).to_s].join('/')

		#empty execution if not test_environment should we have a default test_environment
		(test_package_config["test-environments"] or {}).map { |test_environment_name,test_environment_content|
			scenarios = JSON.parse(Net::HTTP.get(URI(MECHATOUCH_URL+"/branches/name:"+test_package_config["branch"]+"/scenarios.json?tag="+test_package_config["select-tag"])))

			scenarios.map { |scenario|
				tags = { name: [scenario['reference']]}


				prepared_requirements =  [{
											  type: 'DUT',
											  mfgimage: {
												  package: device_image_path,
												  path: File.basename(device_image_path)
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
		p ['locating target for..',regexp, archive, package_dir].join(' ')

		return File.basename(archive) if archive =~ %r[#{regexp.delete('/')}]

		image_path = Find.find(package_dir).find{ |e| if !FileTest.directory?(e) then (e =~ /hex|bin|zip|ipk|vmdk|ovf|py|sh/) && (e =~ %r[#{regexp.delete('/')}]) end }

		if image_path
			p image_path[package_dir.size..-1]
		else
			puts "Package does not include flashable image !"
		end
	end

	##INFO:
	##USED IN: scheduler-worker:executor.rb - used for storage<->task dir linkage
	def self.link_archive_to_task_folder(package_path,task_id)
		package_name = File.basename(package_path)
		prepared_local_unpack_directory = [SCHEDULER_WORKER_ROOT,'storage','unpacked',package_name].join('/')
		prepared_local_unpack_directory_contents = Dir[prepared_local_unpack_directory+'/*']
		task_directory = [SCHEDULER_WORKER_ROOT,"storage","tasks",task_id].join('/')

		# INFO: Symlink every item in unpack folder to task folder.
		prepared_local_unpack_directory_contents.each { |symlink_source|
			symlink_target = [task_directory,File.basename(symlink_source)].join('/')
			puts ['Linking',symlink_source,'to',symlink_target].join(' ')
			begin
				File.symlink(symlink_source,symlink_target)
			rescue Errno::EEXIST
				puts 'File exists !'
			end

		}
	end

	##INFO:
	##USED IN: scheduler-worker/resources - verifies if jlink flashing has been successful.
	def self.verify_jlink(output)
		# INFO: Raises FlashingError if success or skip messages are not in JLink output to stdout.
		puts "*"*40 + " Begin JLink " + "*"*40
		puts output
		puts "*"*40 + " End JLink " + "*"*40

		success_message = /Flash programming performed.*O\.K\./m
		skip_message = /Flash download skipped. Flash contents already match/m
		if not (output.match(success_message) or output.match(skip_message))
			raise FlashingError
		else
			puts "Successfully flashed !"
			return true
		end
	end

	##INFO:
	##USED IN: scheduler-worker:executor.rb - to get robot tests ::
	def self.fetch_package(options)
		target_url = options[:target_url]
		tries = 0
		begin
			p "Fetching: #{target_url}"
			# INFO: Filename for archive.
			target_filename = File.basename(target_url)

			# INFO: Download RPMs from server to storage/rpms
			prepared_local_repo_directory = [SCHEDULER_WORKER_ROOT,'storage','rpms'].join('/')

			# INFO: Absolute path for archive
			file_fullpath = [prepared_local_repo_directory,target_filename].join('/')

			# INFO: Create lockfile at SCHEDULER_WORKER_ROOT/storage/rpms/<target_filename>_LOCK
			self.lockdir(file_fullpath+'_LOCK') {
				p ['Downloading to',file_fullpath].join(' ')
				if not File.file?(file_fullpath)
					begin
						downloaded_file = File.open(file_fullpath, 'wb')
						request = Typhoeus::Request.new(target_url,ssl_verifyhost: 0, ssl_verifypeer: false)
						request.on_headers do |response|
							if response.code != 200
								raise RequestUnsuccessful
							end
						end
						request.on_body do |chunk|
							downloaded_file.write(chunk)
						end
						request.on_complete do |response|
							downloaded_file.close
						end
						request.run
					rescue RequestUnsuccessful
						if tries < 5 then
							puts ['Retry in 10 seconds.',tries+1,'of 5'].join(' ')
							sleep(10)
							tries = tries + 1
							downloaded_file.close
							retry
						end
						raise RequestUnsuccessful
					end
					self.validate_package(file_fullpath)
				end
			}
			return file_fullpath
		end
	end



	##INFO:
	##USED IN: fetch_binary_packages_from_obs in helpers.rb - to validate rpm packages.
	def self.validate_package(package_path)
		file_extension = File.extname(package_path)
		if file_extension != ".rpm"
			puts ['File extension is:',file_extension,',cannot validate this file, skipping.'].join(' ')
			return true
		end
		# INFO: Validates incoming rpm package.
		validate_command = ['rpm','-K',package_path].join(' ')
		validate_output = `#{validate_command}`
		# INFO: If validate output does not have OK string, delete corrupt package and raise a CorruptPackageError.
		unless validate_output.match(/OK/)
			File.delete(package_path)
			raise CorruptPackageError
		end
		true
	end


	##INFO:
	##USED IN: scheduler-server:task_procedures/task.rb - to get all required packages ::
	def self.fetch_binary_packages_from_obs(destination_directory, project, repo, arch, obs_package_name, binary_package_name_filter,default_project=nil)
		puts "Working directory is: "+Dir.pwd

		tries = 0
		begin
			package_info_url = [OBS_URL,'build',project,repo,arch,obs_package_name].join('/')
			$stderr.puts "Grab binary list from: #{package_info_url}"
			package_info = RestClient::Request.new(
				:method => :get,
				:url => package_info_url,
				:user => OBS_USER,
				:password => OBS_PASS,
				:verify_ssl => OpenSSL::SSL::VERIFY_NONE
			).execute
			begin
				found_binaries = Hash.from_xml(package_info)["binarylist"]["binary"]
				files_to_download = found_binaries.map { |binary| binary["filename"] }.select { |filename|
					filename =~ binary_package_name_filter
				}
			rescue => e
				#if files_to_download.size == 0
				puts "Could not find target: "+binary_package_name_filter.to_s
				raise NotOnOBS
			end

			files_to_download.map { |file_to_download|
				url = package_info_url+"/"+file_to_download
				local_dir = [destination_directory,'storage','rpms',obs_package_name].join('/')
				local_path = [local_dir, file_to_download].join('/')

				FileUtils::mkdir_p(local_dir)

				puts ['Fetching package from: ',url,'to',local_path].join(' ')

				SchedyHelper.lockdir(local_path+'_LOCK') {
					next local_path if File.file?(local_path)
					File.open(local_path, "w") { |file| file.write(
													 binary = RestClient::Request.new(
														 :method => :get,
														 :url => url,
														 :user => OBS_USER,
														 :password => OBS_PASS,
														 :verify_ssl => OpenSSL::SSL::VERIFY_NONE
													 ).execute)
					}
					SchedyHelper.validate_package(local_path)
				}
				puts 'Downloaded: '+local_path
				local_path
			}

		rescue RestClient::ExceptionWithResponse => err
			if tries > 3
				raise NotOnOBS
			elsif tries > 2 && default_project
				puts [err,'For once, will retry 5 seconds later with a default project...'].join(' ')
				sleep(5)
				project = default_project
				tries = tries + 1
				retry
			end
			puts [err,'Will retry 5 seconds later.',tries+1,'of 3'].join(' ')
			sleep(5)
			tries = tries + 1
			retry
		end
	end



	##INFO:
	##USED IN: scheduler-server:task_procedures/task.rb - to get list of robot tests for task creation
	def self.parse_robot_tests_list(test_package_name,options=nil)

		robot_parser_script =
			['python '+SCHEDULER_SERVER_ROOT,'project','creator','suite_parser.py'].join('/')

		robot_file_path =
			[SCHEDULER_SERVER_ROOT,'storage','unpacked',File.basename(test_package_name)].join('/')

		test_parse_command = [robot_parser_script,robot_file_path].join(' ')

		puts "Parsing robot tests by : #{test_parse_command}"
		parser_output = `#{test_parse_command}`

		if parser_output.blank? then return [] end

		test_suite_json = JSON.parse(parser_output)

		if not options.nil? and options[:intersection]
			test_suite_json = test_suite_json.select { |test_case|
				!(test_case["tags"] & options[:intersection]).empty? }
		end

		if not options.nil? and options[:minus]
			test_suite_json = test_suite_json.select { |test_case|
				(test_case["tags"] & options[:minus]).empty? }
		end

		test_suite_json

	end

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
			parsed_tag_string =  if tag.strip.match(/(.*)_(.*)/) or next
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
