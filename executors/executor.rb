#!/usr/bin/env ruby

require_relative './base.rb'

class RobotExecutor < BaseExecutor

	def initialize()
		super()
	end

	def preprocess()
		@logger.info "Robot Preprocessing started."
		super()
		create_robot_resource_file()
		@logger.info "Robot Preprocessing finished.."

	end

	def execute_task()
		@logger.info "Robot Task Execution started."
		super()
		@logger.info "Robot Task Execution finished.."
	end

	def postprocess()
		@logger.info "Robot Postprocessing started."
		super()
		robot_post_processing()
		@logger.info "Robot Postprocessing finished."
	end


	def create_robot_resource_file()
		@logger.info "Creating resource file for #{@task["test_name"]}"

		File.open("resource_ci.robot","w") { |file|

			file.write("*** Variables ***\n")

			file.write(@task["actors"].map { |actor_name, actor_data|
						#Define a resource row, use database description of actors.
						resource_row = "&{#{actor_name}}    id=#{actor_name}   " +actor_data['description'].map{ |key, value| "#{key}=#{value}" }.join("    ")
						#Check if actors with matching roles have 'options' field in test-config.json
						options = @task["requirements"].find{|req| req["role"] == actor_name}["options"]
						#If options exist, append them to resource row.
						if not options.nil?
							resource_row = [resource_row,options].join("   ")
						end
						#Return the final resource row.
						resource_row
					}.join("\n"))

			file.write("\n")
			#If this @task has resource groups defined in its test-config.json, use some arcane magic of data wrangling to group those resources. Arrays of [role,group_key,group_value] are grouped by group_value and then mapped to create rows of 'group_key   group_value=role'.
			if @task["has_resource_groups"] == "true"
				grouped_resources = {}
				@task["requirements"].map { |requirement|
					requirement["resource-groups"].map { |resource_group| [requirement["role"],resource_group[0],resource_group[1]] }.group_by { |arr| arr[2] } }.map { |resources| resources.map { |resource_info| (grouped_resources[resource_info[0]] ||= []) << resource_info[1] }}
				file.write(grouped_resources.map { |resource_group,resource_info| "&{#{resource_group}}    "+resource_info.flatten(1).map{ |info| "#{info[1]}=&{#{info[0]}}"}.join("    ") }.join("\n"))
			end

			file.write("\n")
		}
	end

	#INFO: Post processing function for robot framework results.
	#Uses result_parser -which uses Teresa gem- for parsing XUnit files produced by pybot.

	def robot_post_processing()

		@logger.info "Post processing robot tests #{@task["test_name"]} @ #{@task_directory}"

		robot_file_path = [@task_directory,'xunit.xml'].join('/')
		value_endpoint = [@SCHEDULER_URI,'tasks',@task["id"],"tags"].join('/')
		gemfile_path = [@SCHEDULER_WORKER_ROOT,'project','bin','Gemfile'].join('/')

		if not File.file?(robot_file_path)
			@logger.info 'xunit.xml not found ! no result will be reported.'
			return 0
		end

		result_parser_path = [@SCHEDULER_WORKER_ROOT,'project','bin','result_parser'].join('/')
		robot_result_parser_script = "BUNDLE_GEMFILE='#{gemfile_path}' #{result_parser_path}"
		test_parse_command = "#{robot_result_parser_script}  #{robot_file_path}"
		@logger.info "Parsing robot test results, executing command : #{test_parse_command}"
		stats_json = JSON.parse(`#{test_parse_command}`)[0]
		result = if (stats_json["result"] == "passed") then "PASS" else "FAIL" end
		reason = stats_json["reason"]
		@logger.info "Results JSON: #{stats_json} Uploading to server."
		result_res = Typhoeus.post(value_endpoint, body: {task_id: @task["id"], property: "result", value: result })
		reason_res = Typhoeus.post(value_endpoint, body: {task_id: @task["id"], property: "reason", value: reason })
		@logger.info "#{result} is result and #{@task['test_environment']} test env is this."
		if result=="FAIL" and @task["test_environment"] == "HAS_COREDUMPS"
			fetch_coredumps()
		end

		return 0
	end


def fetch_coredumps()
	vm_name = @task["actors"]["DUT"]["description"]["name"]
	qcow_mount_directory = "#{@SCHEDULER_WORKER_ROOT}/storage/vm-images/#{vm_name}"
	coredump_dir = "core_dump"
	mount_order = ["XDG_RUNTIME_DIR=/tmp/ LIBGUESTFS_BACKEND=direct","guestmount","-a","#{@SCHEDULER_WORKER_ROOT}/storage/vm-images/#{vm_name}.qcow2","-m","/dev/sda2", "--ro", qcow_mount_directory].join(" ")
	unmount_order = ["XDG_RUNTIME_DIR=/tmp/ LIBGUESTFS_BACKEND=direct","guestunmount",qcow_mount_directory].join(" ")
	fetch_coredumps = ["cp","-r","#{qcow_mount_directory}/#{coredump_dir}",@task_directory].join(" ")
	mkdir_mount_directory = ["mkdir","#{qcow_mount_directory}/#{coredump_dir}"].join(" ")
	@logger.info "Fetching coredumps."
	@logger.info "Mounting disk image to #{qcow_mount_directory}."
	@logger.info "Executing command: #{mount_order}"

	`#{mount_order}`

	if $?.exitstatus != 0
		@logger.error "Failed to mount disk image !"
		return 1
	end

	available_coredumps = Dir.entries("#{qcow_mount_directory}/#{coredump_dir}").select { |entry| File.exists? entry }
	@logger.info "Directories available:\n #{Dir.entries(qcow_mount_directory).join(' ')}"
	@logger.info "Available coredumps:\n #{available_coredumps.join("\n")}"

	if not available_coredumps.length > 0
		@logger.info "No coredumps found !"
		return 0
	end

	@logger.info "Retrieving coredumps from #{qcow_mount_directory} to #{@task_directory}."
	@logger.info "Executing command: #{fetch_coredumps}"

	`#{fetch_coredumps}`

	if $?.exitstatus != 0
		@logger.error "Failed to fetch coredumps !"
		return 1
	end

	fetched_coredumps = Dir.entries("#{@task_directory}") & available_coredumps

	if (fetched_coredumps).length > 0
		@logger.info "Successfully fetched files: #{fetched_coredumps}."
	else
		@logger.error "Failed to fetch coredumps !"
	end

	@logger.info "Unmounting disk image to #{qcow_mount_directory}."

	`#{unmount_order}`

	if $?.exitstatus != 0
		@logger.error "Failed to unmount the disk image !"
		return 1
	end
end

end

robot_execution = RobotExecutor.new()

robot_execution.preprocess()

robot_execution.execute_task()

robot_execution.postprocess()
