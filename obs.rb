require 'active_support/core_ext/hash'   #for Hash.from_xml

require_relative 'net.rb'
require 'rest-client'

class OBS
	attr_reader :url, :user, :password


	def initialize(url:, user: nil, password: nil)
		@url, @user, @password = url, user, password
	end


	def package(**args)
		Package.new(obs: self, **args)
	end


	class Package

		attr_reader :url, :obs


		def initialize(obs:, project:, default_project: nil , repo:, default_repo: nil , arch:, default_arch: nil, package_name:)
			@obs, @project, @default_project, @repo, @default_repo, @arch, @default_arch, @package_name = obs, project, default_project, repo, default_repo, arch, default_arch, package_name
			@url = [@obs.url,'build',project,repo,arch,package_name].join('/')
			@default_url = [@obs.url,'build',(project || default_project),(repo || default_repo),(arch || default_arch),package_name].join('/')
			#@default_url = [@obs.url,'build',(default_project),(default_repo),(default_arch),package_name].join('/')
		end

		def get_repo_data(options: nil)
			repo = {}
			p "Constructing repourl for package: #{@package_name}"

			@repo_url = OBS_REPO_BASE_URL+'/'+[@project,@repo].join('/').gsub(":",":/")+"/#{@project}.repo"

			RestClient::Request.execute(:url => @repo_url,:method => :get, :verify_ssl => false, :user => @obs.user, :password => @obs.password) { |response, request, result|
				if response.code == 200 then repo["#{@project}/#{@repo}"] = {"priority" => 1, "proxy" => nil, "url" => @repo_url} end
			}

			p "Constructed repourl : #{@repo_url}"
			@fallback_repo_url = OBS_REPO_BASE_URL+'/'+[@default_project,@default_repo].join('/').gsub(':',':/')+"/#{@default_project}.repo"

			p "Constructed fallbackrepourl : #{@fallback_repo_url}"

			RestClient::Request.execute(:url => @fallback_repo_url,:method => :get, :verify_ssl => false, :user => @obs.user, :password => @obs.password) { |response, request, result|
				if response.code == 200 then repo["#{@default_project}/#{@default_repo}"] = {"priority" => 10, "proxy" => nil, "url" => @fallback_repo_url} end
			}
			p "Result : #{repo}"
			repo
		end


		def binaries
			first_try = true
			begin
				package_info = Net::get(url: @url, user: @obs.user, password: @obs.password)

				if Hash.from_xml(package_info)["binarylist"] == nil
					raise Net::RequestUnresolvable.new("Empty binarylist")
				end

				result = Hash.from_xml(package_info)["binarylist"]["binary"].map { |binary|
					Binary.new(package: self, name: binary["filename"])
				}
			rescue Net::RequestUnresolvable => error
					p "Attempted: #{@url.inspect}, Fallback: #{@default_url}"
					@url = @default_url
					if first_try
						first_try = false
						retry
					else
						raise Net::RequestUnresolvable.new(error)
					end
			end
			result
		end
	end


	class Binary

		attr_reader :name


		def initialize(package:, name:)
			@package, @name = package, name
			@url = @package.url + '/' + @name
		end

		def download(target_directory:)
			Net::download(url: @url, target_directory: target_directory, user: @package.obs.user, password: @package.obs.password) { |body|
				case File.extname(@name)
				when '.rpm'
					open("|rpm -K -", "w+") { |rpm|
						rpm.write(body)
						rpm.close_write
						rpm.read
					} =~ /OK/
				else
					body.size > 0
				end
			}
		end
	end
end
