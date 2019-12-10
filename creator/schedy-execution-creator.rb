require_relative "workitem-parser.rb"
require_relative "../helpers.rb"
require_relative "../obs.rb"
require_relative '../archive.rb'
require_relative "schedy-api.rb"

STDOUT.puts "stdout"
STDERR.puts "stderr"

def workitem_process(workitem)
	workitem_description = workitem_parse(workitem)
	execution_description = workitem_description_to_execution_description(workitem_description)
	execution_description[:data] = workitem
	schedy = SchedyClient.new(url: SCHEDULER_URI)
	schedy.execution_create(execution_description)
rescue Net::RequestUnsuccessful, Net::RequestUnresolvable
	puts "OBS failed to deliver. ACK-ing the WI."
	raise PermanentWorkItemError
end


def workitem_description_to_execution_description(workitem_description)
	obs = OBS.new(url: OBS_URL, user: OBS_USER, password: OBS_PASS)
	config = get_config(workitem_description,workitem_description.triggered_by_package,obs)
	config_gating_threshold = config["gating_threshold"] || nil
	config_gating_tag = config["gating_tag"] || nil
	tasks = ([create_tasks(workitem_description,obs)] or []).compact.flatten
	tags = {
		package: [workitem_description.triggered_by_package],
		project: [workitem_description.project],
		author: [workitem_description.author],
		gerrit: [workitem_description.url_gerrit],
		obs: [workitem_description.url_obs],
		threshold: [config_gating_threshold],
		gating_tag: [config_gating_tag],
		eventtype: [workitem_description.event_type],
	}.reject { |key, value| value.compact.empty? }
	hooks = workitem_description.hooks ? JSON.parse(JSON.dump(workitem_description.hooks)) : { "finished": ["bureaucrat.rb","data_exporter.rb","data_exporter_2.rb"] }

	{tasks: tasks, creator: "CI", tags: tags, hooks: hooks}
end


def get_config(description, package_name, obs)

	if package_name && File.file?('config/'+package_name+".json")
		puts "Found %s file, using preferentially instead of package-supplied ci-config"%['config/'+package_name+".json"]
		return get_event_type_config(JSON.load(File.read('config/'+package_name+".json")), event_type_recursion_path: [description.event_type], event_type_config: {})
	end

	package = obs.package(project: description.package_project[package_name], repo: description.package_repository[package_name], arch: description.package_arch[package_name], package_name: package_name, default_project: description.default_project)
	config_packages = package.binaries.select { |binary| binary.name =~ /test-config/ }

	if config_packages.size == 0
		puts  "No config packages found for obs-package ! Package: %p:"%[package_name]
		raise PermanentWorkItemError
	elsif config_packages.size > 1
		puts  "Too many config packages found for obs-package ! Package: %p:"%[package_name]
		raise PermanentWorkItemError
	end

	downloaded_config_package_path = config_packages[0].download(target_directory: SCHEDULER_SERVER_ROOT+'/storage/rpms')

	config_package_dir = Archive.extract(archive_path: downloaded_config_package_path, target_directory: SCHEDULER_SERVER_ROOT+'/storage/unpacked', set_read_only: true)
	config_file_path = config_package_dir + "/usr/share/#{package_name}/test/ci-config/test-config.json"
	if not File.file?(config_file_path) then p 'no config package'; raise PermanentWorkItemError end

	begin
		config = open(config_file_path) { |f| JSON.load(f.read) }

	rescue
		puts "JSON parsing error, blame config owner and EJECT !"
		raise PermanentWorkItemError
	end
	get_event_type_config(config, event_type_recursion_path: [description.event_type], event_type_config: {})
end


def get_event_type_config(config, event_type_recursion_path:, event_type_config:)
	if not config[event_type_recursion_path[-1]] then p "undefined event type! #{event_type_recursion_path.to_s}"; raise PermanentWorkItemError end
	(config[event_type_recursion_path[-1]]["include"] or []).each { |include_event_type|
		raise "Config file (event-type %s) requested inclusion of nonexistent event-type: %s"%[event_type_recursion_path[-1].inspect, include_event_type.inspect] if not config.has_key?(include_event_type)
		raise "Config file has cyclic dependency: "+event_type_recursion_path.inspect if event_type_recursion_path.include? include_event_type
		event_type_config = get_event_type_config(config, event_type_recursion_path: event_type_recursion_path + [include_event_type], event_type_config: event_type_config)
	}
	overlay(event_type_config, config[event_type_recursion_path[-1]])
end


def overlay(value1, value2)
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
		next_package_description = config["required-packages"].select { |package| package["name"] == obs_package }[0]

		if next_package_description
			if not description.package_arch[obs_package] then description.package_arch[obs_package] = next_package_description["default_arch"] end
			if not description.package_repository[obs_package] then  description.package_repository[obs_package] = next_package_description["default_repo"] end
			if not description.package_project[obs_package] then description.package_project[obs_package] = next_package_description["default_project"] || description["default_project"] end

		end
		collect_properties(description, config_files, dependency_path + [obs_package], overridden_properties.dup, configuration) if not dependency_path.include?(obs_package)
	}
end


def create_tasks(description, obs)
	tasks = []
	config_files = Hash.new { |hash, package| hash[package] = get_config(description, package, obs) }
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

	raise PermanentWorkItemError if conflict
	required_packages = Hash.new("")
	required_repos = Hash.new("")
	tasks = configuration.map { |package_name,test_packages|
		puts "Required packages for: #{package_name}"
		extracted_required_packages = config_files[package_name]["required-packages"].map { |package_data|
			package = obs.package(
				project: description.package_project[package_data["name"]],
				repo: package_data["repo"],
				arch: package_data["arch"],
				default_project: package_data["default_project"],
				default_arch: package_data["default_arch"],
				default_repo: package_data["default_repo"],
				package_name: package_data["name"])
			required_repos = required_repos.merge(package.get_repo_data)
			package.binaries.map { |binary|
				next if binary.name  !~ /((#{package_data["name"]}-[0-9]).*(rpm))|((#{package_data["name"]}-robot-tests)|(#{package_data["name"]}-test-config).*(rpm))|(zip)|(ipk)|(whl)|(swu)/
				downloaded_config_package_path = binary.download(target_directory: SCHEDULER_SERVER_ROOT+'/storage/rpms')
				Archive.extract(archive_path: downloaded_config_package_path, target_directory: SCHEDULER_SERVER_ROOT+'/storage/unpacked', set_read_only: true)
			}
		}.flatten.compact
		if config_files[package_name]["required-container-packages"]
		required_container_packages = config_files[package_name]["required-container-packages"].each_pair { |container_name,package|
			package.each_pair { |package_name, package_data|
				required_packages[package_data["name"]] = { "container" => container_name, "version" => nil }
			}
		}
		end

		puts "Extracted required packages:"
		extracted_required_packages.each { |package| puts "\t"+package.inspect }

		test_packages.map { |test_package_name, test_package_config|
			SchedyHelper.generate_tasks({
				obs: obs,
				test_package_name: test_package_name,
				test_package_config: test_package_config,
				package_name: package_name,
				description: description,
				required_packages: required_packages,
				required_repos: required_repos,
				extracted_required_packages: extracted_required_packages
			})
		}

	}.flatten.compact

	tasks = tasks * description.multiplier
	tasks
end
