ENV['BUNDLE_GEMFILE']=File.expand_path(File.dirname(__FILE__)) + "/Gemfile"

require 'bundler/setup'
require 'awesome_print'
require 'typhoeus'
require 'active_support/core_ext/hash'
require 'jsonclient'
require 'erb'
require 'logger'

require_relative '../config.rb'
require_relative '../net.rb'
require_relative '../archive.rb'



	 #         MAKE                          EXECUTORS                          GREAT
	 # +-------------------+           +-------------------+            +-------------------+
	 # |                   |           |                   |            |                   |
	 # |    PREPROCESS     +----------->   EXECUTE TASKS   +------------>    POSTPROCESS    |
	 # |                   |           |                   |            |                   |
	 # +-------------------+           +-------------------+            +-------------------+
	 #         MAKE                          EXECUTORS                          GREAT

class BaseExecutor

	def initialize()

		@logger = Logger.new(STDOUT)
		@logger.info "Base initialization started."
		@task_raw = File.read('task.json')
		@task = JSON.parse(@task_raw)
		@task_name = @task["test_name"]
		@task_directory = Dir.pwd
		@task_id = @task["id"]
		@execution_id = @task["execution_id"]
		@SCHEDULER_SERVER_ROOT = SCHEDULER_SERVER_ROOT
		@SCHEDULER_WORKER_ROOT = SCHEDULER_WORKER_ROOT
		@SCHEDULER_URI = SCHEDULER_URI
		@EXTERNAL_SCHEDULER_URI = EXTERNAL_SCHEDULER_URI
		parse_task_config()

		@logger.info "Processing Task with ID: #{@task['id']}"
		@logger.info "Base initialization ended."
	end

	def preprocess()
		@logger.info "Base Preprocessing started.."
		get_task_assets()
		@logger.info "Base Preprocessing finished."
	end

	def execute_task()
		@logger.info "Base Task Execution started."
		execute_command_line()
		@logger.info "Base Task Execution finished."
	end

	def postprocess()
		@logger.info "Base Postprocessing started."
		@logger.info "Base Postprocessing finished."
	end


	def parse_task_config()
		@logger.info "Parsing task configuration"
		#<variables-in-config>
		task = @task
		test_name = @task_name
		task_dir = @task_directory
		#</variables-in-config>
		## some stuff to keep json format sane.
		task_evaluated = JSON.parse(ERB.new(JSON.dump(JSON.parse(@task_raw))).result(binding))
		@task = task_evaluated
	end

	def symlink_assets(source:, destination:)

		@logger.info "Symlinking task assets from #{source} to #{destination}"

		# INFO: Symlink every item in unpack folder to task folder.
		Dir[source+'/*'].each { |symlink_source|
			symlink_target = [destination,File.basename(symlink_source)].join('/')
			@logger.info "Linking #{symlink_source} to #{symlink_target}"
			begin
				File.symlink(symlink_source,symlink_target)
			rescue Errno::EEXIST
				@logger.info 'File exists !'
			end

		}

	end

	#XXX: Confusing naming, task assets or test package ? Task creation needs a change as well.
	def get_task_assets()

		@logger.info "Fetching task assets for: #{@task['id']}"
		if @task["test_package"]
			task_assets = Net.download(url: @task["test_package"],target_directory: @SCHEDULER_WORKER_ROOT+'/storage/rpms',maximum_retries: 5)
			unpacked_task_assets = Archive.extract(archive_path: task_assets,target_directory: @SCHEDULER_WORKER_ROOT+'/storage/unpacked',set_read_only: true)
			symlink_assets(source: unpacked_task_assets, destination: @task_directory)
		end

	end

	def execute_command_line()
		@logger.info "Executing task: #{@task['test_name']}"
		current_directory = Dir.pwd
		environment_variables = @task["environment_variables"]
		task_command = @task["command_line"]
		command_line = [environment_variables,task_command].join(' ')
		puts command_line
		puts `#{command_line}`
	end

	def fetch_coredumps()
		vm_name = @task["actors"]["DUT"]["description"]["name"]

		coredump_dir = "core_dumps"

		mount_order = ["guestmount","-a","#{@SCHEDULER_WORKER_ROOT}/storage/vm-images/#{vm_name}.qcow2","-m","/dev/sda2", "--ro", "#{@SCHEDULER_WORKER_ROOT}/storage/vm-images/#{vm_name}"].join(" ")

		unmount_order = ["guestunmount",mount_target].join(" ")

		fetch_coredumps = ["cp","-r","#{mount_target}/#{coredump_dir}",task_dir].join(" ")

		mkdir_mount_directory = ["mkdir","#{mount_target}/#{coredump_dir}"].join(" ")
		@logger.info "Fetching coredumps."

		@logger.info "Mounting disk image to #{qcow_mount_directory}."

		@logger.info "Executing command: #{mount_order}"

		`#{mount_order}`

		if $?.exitstatus != 0
			@logger.error "Failed to mount disk image !"
			return 1
		end

		available_coredumps = Dir.entries("#{mount_target}/#{coredump_dir}")

		@logger.info "Available coredumps:\n #{available_coredumps.join("\n")}"

		@logger.info "Retrieving coredumps from #{qcow_mount_directory} to #{task_dir}."

		@logger.info "Executing command: #{fetch_coredumps}"

		`#{fetch_coredumps}`

		if $?.exitstatus != 0
			@logger.error "Failed to fetch coredumps !"
			return 1
		end

		fetched_coredumps = Dir.entries("#{task_dir}") & available_coredumps

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
