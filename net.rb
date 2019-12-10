require 'typhoeus'

require_relative 'terminal.rb'
require_relative 'ipc.rb'

module Net

	class ValidationFailed < IPC::SoftFail; end
	class RequestUnresolvable < IPC::SoftFail; end
	class RequestUnsuccessful < IPC::SoftFail;
		attr_reader :response
		def initialize(response)
			@response = response
		end
		def code_to_s
			@response.code.to_s
		end
	end


	def self.get(url:, maximum_retries: 2, user: nil, password: nil, &validator)
		body = ""
		tries = 0
		begin
			options = {
				ssl_verifyhost: 0,
				ssl_verifypeer: false,
				#verbose: true,
				followlocation: true,
				timeout: 6000
			}
			options[:userpwd] = user+":"+password if user and password
			request = Typhoeus::Request.new(url, options)
			request.on_headers do |response|
				raise RequestUnsuccessful.new(response) if response.code != 200
			end
			request.on_body do |chunk|
				body.concat(chunk)
			end
			request.on_failure do |response|
				raise RequestUnsuccessful.new(response)
			end
			request.on_complete do |response|
				raise ValidationFailed if validator and not validator.call(body)
			end
			request.run
		rescue RequestUnsuccessful, ValidationFailed => error
			if tries < maximum_retries then
				fp "GET failed (#{error.code_to_s})", "retring in 5 seconds (retry ", tries+1, ' of ', maximum_retries, ") url: #{url}"
				sleep(5)
				tries = tries + 1
				retry
			end
			raise RequestUnresolvable.new(error.code_to_s)
		end
		body
	end


	def self.download(url:, target_directory:, maximum_retries: 5, user: nil, password: nil, &validator)
		target_path = target_directory + "/" + File.basename(url)
		IPC.lockdir(target_path + '_LOCK') {
			next if File.file?(target_path)
			data = Net::get(url: url, maximum_retries: maximum_retries, user: user, password: password, &validator)
			File.open(target_path, 'wb') { |downloaded_file| downloaded_file.write(data) }
		}
		target_path
	end

end
