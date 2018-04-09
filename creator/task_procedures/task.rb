require 'erb'

class TaskLogic < TaskProcedure


	def self.get_config(description, obs_package)
		return get_event_type_config(open('config/'+obs_package+".json") { |f| JSON.load(File.read(f)) }, event_type_recursion_path: [description.event_type], event_type_config: {}) if obs_package && File.file?('config/'+obs_package+".json")
		config_packages = SchedyHelper.fetch_binary_packages_from_obs(
			SCHEDULER_SERVER_ROOT,
			description.package_project[obs_package],
			description.package_repository[obs_package],
			desxcription.package_arch[obs_package],
			obs_package,
			/test-config/)
		if config_packages.size == 0
			p  "No config packages found for obs-package ! Package: %s:"%[obs_package]
			raise NotOnOBS
		end
		#raise "No config packages found for obs-package ! Package: %s:"%[package] if config_packages.size == 0
		config_package_dir = SchedyHelper.process_obs_archive(SCHEDULER_SERVER_ROOT, config_packages[0])
		config_file_path = config_package_dir + "/usr/share/#{obs_package}/test/ci-config/test-config.json"
		raise "Config package does not include json file." if not File.file?(config_file_path)
		config = open(config_file_path) { |f| JSON.load(f.read) }
		get_event_type_config(config, event_type_recursion_path: [description.event_type], event_type_config: {})
	end


	def self.get_event_type_config(config, event_type_recursion_path:, event_type_config:)
		(config[event_type_recursion_path[-1]]["include"] or []).each { |include_event_type|
			raise "Config file (event-type %s) requested inclusion of nonexistent event-type: %s"%[event_type_recursion_path[-1].inspect, include_event_type.inspect] if not config.has_key?(include_event_type)
			raise "Config file has cyclic dependency: "+event_type_recursion_path.inspect if event_type_recursion_path.include? include_event_type
			event_type_config = get_event_type_config(config, event_type_recursion_path: event_type_recursion_path + [include_event_type], event_type_config: event_type_config)
		}
		overlay(event_type_config, config[event_type_recursion_path[-1]])
	end


	def self.overlay(value1, value2)
		if value1.kind_of? Hash and value2.kind_of? Hash
			(value1.keys+value2.keys).uniq.map { |key|
				[key, overlay(value1[key],value2[key])]
			}.to_h
		else
			value2 or value1
		end
	end


	def self.collect_properties(description, config_files, dependency_path, overridden_properties, configuration)
		return if not config = config_files[dependency_path[-1]]
		(config["test-packages"] or {}).each_pair { |obs_package, binary_packages|
			binary_packages.each_pair { |binary_package, binary_package_config|
				binary_package_config.each_pair { |key, value|
					property = [obs_package, binary_package, key]
					next if overridden_properties.include? property
					overridden_properties << property
					configuration[obs_package][binary_package][key] << [dependency_path, value]
				}
			}
		}
		(config["test-packages"] or {}).each_pair { |obs_package, binary_packages|
			collect_properties(description, config_files, dependency_path + [obs_package], overridden_properties.dup, configuration) if not dependency_path.include?(obs_package)
		}
	end


	def self.create_tasks(description)
		tasks = []
		config_files = Hash.new { |hash, package| hash[package] = get_config(description, package) }
		configuration = Hash.new { |h,k| h[k] = Hash.new { |h2,k2| h2[k2] = Hash.new { |h3,k3| h3[k3] = [] }} }
		collect_properties(description, config_files, [description.triggered_by_package], [], configuration)
		puts "CI Configuration:"
		conflict = false
		configuration.each_pair { |obs_package, binary_package_config|
			puts "\t"+obs_package
			binary_package_config.each_pair { |binary_package, properties|
				puts "\t\t"+binary_package
				properties.keys.each { |property|
					if (grouped_by_value = properties[property].group_by { |config, value| value }).size > 1
						puts "\t\t\tCONFLICTING values requested for %s:"%[property]
						grouped_by_value.each { |value, configs|
							configs.each { |config, _|
								puts "\t\t\t\t%s wants %s"%[config[-1].ljust(30), value.inspect]
							}
						}
						conflict = true
					else
						puts "\t\t\t%s set %s to %s"%[properties[property][0][0][-1].ljust(30), property.ljust(20), properties[property][0][1].inspect]
						properties[property] = properties[property][0][1]
					end
				}
			}
		}

		raise "CI Configuration loading failed" if conflict

		tasks = configuration.map { |package_name,test_packages|

			extracted_required_packages = config_files[package_name]["required-packages"].map { |obs_package|


				SchedyHelper.fetch_binary_packages_from_obs(SCHEDULER_SERVER_ROOT,
															description.package_project[obs_package["name"]] || "",
															obs_package["repo"],
															obs_package["arch"],
															obs_package["name"],
															/((#{obs_package["name"]}-[0-9]).*(rpm))|((#{obs_package["name"]}-robot-tests).*(rpm))|(vmdk)|(ovf)|(ipk)/).each { |binary_package|
					SchedyHelper.process_obs_archive(SCHEDULER_SERVER_ROOT, binary_package)
				}
			}


			test_packages.map { |test_package_name, test_package_config|

				SchedyHelper.generate_tasks({
												test_package_name: test_package_name,
												test_package_config: test_package_config,
												package_name: package_name,
												description: description,
												extracted_required_packages: extracted_required_packages
											}
										   )
			}

		}.flatten.compact

		tasks = tasks * description.multiplier
		tasks
	end

end
