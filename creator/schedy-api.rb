require 'rest_client'
require 'json'

class SchedyClient

	def initialize(url:)
		@url = url
	end


	def execution_create(execution)
		post_response = RestClient.post(@url+'/executions',JSON.dump({execution: execution}), :content_type => :json, :accept => :json)
		return false if not post_response.code.to_s == "200"
		JSON.parse(post_response.body)
	end

end
