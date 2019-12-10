#!/usr/bin/env ruby

require_relative './base.rb'

class GoogleTestExecutor < BaseExecutor

	def initialize()
		super()
	end

	def preprocess()
		@logger.info "GoogleTest Preprocessing started."
		super()
		GoogleTestExecutor.create_googletest_resource_file()
		@logger.info "GoogleTest Preprocessing finished.."

	end

	def execute_task()
		@logger.info "GoogleTest Task Execution started."
		super()
		@logger.info "GoogleTest Task Execution finished.."
	end

	def postprocess()
		@logger.info "GoogleTest Postprocessing started."
		super()
		GoogleTestExecutor.googletest_post_processing()
		@logger.info "GoogleTest Postprocessing finished."
	end

	#INFO: Post processing function for google framework results.
	def self.googletest_post_processing()
		@logger.info "Post processing google tests #{@task["test_name"]} @task_directory"
		$scheduler_uri ||= 'http://scheduler-server'
		google_file_path = [@task_directory,'googletest_result.xml'].join('/')
		value_endpoint = [$scheduler_uri,'tasks/',@task["id"],"/tags"].join('/')
		gemfile_path = [SCHEDULER_WORKER_ROOT,'project','bin','Gemfile'].join('/')
		if not File.file?(google_file_path)
			@logger.info 'googletest_result.xml not found ! no result will be reported.'
			return 0
		end
		stats_json = JSON.parse(parse_googletest_xml(google_file_path))[0]
		if stats_json["result"] == "passed" then result = "PASS" end
		if stats_json["result"] == "failed" then result = "FAIL" end
		reason = stats_json["message"]
		@logger.info "Results JSON: #{stats_json}. Uploading to server."
		result_res = Typhoeus.post(value_endpoint,body: {task_id: @task["id"], property: "result", value: result })
		reason_res = Typhoeus.post(value_endpoint,body: {task_id: @task["id"], property: "reason", value: reason })
		return 0
	end

	def parse_googletest_xml(source_path)
		outgoing = []
		File.open(source_path) { |f|
			document = Nokogiri::XML(f)
			document.xpath("testsuites/testsuite").each { |suite|
				suite.xpath("testcase").each { |testcase|
					result = :passed
					message = ""
					output = ""
					testcase.xpath("failure|error|skipped").each { |failure|
						result = failure.node_name == "skipped" ? :skipped : :failed
						message = failure["message"]
						output  = failure.text
					}
					outgoing.push({
									  "name"=> testcase["name"],
									  "status" => testcase["status"],
									  "time" => testcase["time"],
									  "result" => result,
									  "message" => message,
									  "output" => output
								  })
				}
			}
		}
		puts JSON.generate(outgoing)

		return JSON.generate(outgoing)
	end
end

googletest_execution = GoogleTestExecutor.new()

googletest_execution.preprocess()

googletest_execution.execute_task()

googletest_execution.postprocess()
