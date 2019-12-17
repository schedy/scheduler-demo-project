require 'shellwords'
require 'fileutils'

class CorruptPackageError < StandardError; end

module Archive

	def self.extract(archive_path:, target_directory:, set_read_only: false)
		puts "Extracting %p to %p"%[archive_path, target_directory]
		directory_to_unpack_to = target_directory + "/" + File.basename(archive_path)
		IPC.lockdir(directory_to_unpack_to+'_LOCK') {
			break directory_to_unpack_to if Dir.exists?(directory_to_unpack_to)
			FileUtils.mkdir_p(directory_to_unpack_to)

			extract_command = case extension = File.extname(archive_path)
			when '.rpm'
				['rpm2cpio',Shellwords.escape(archive_path),'|','cpio','-ivd','2>','/dev/null'].join(" ")
			when ('.zip' or '.whl')
				['unzip',Shellwords.escape(archive_path)].join(" ")
			else
				puts "cannot identify #{extension}, passing"
				['cp',Shellwords.escape(archive_path),'.'].join(" ")#return 0
			end

			puts "Executing: %s"%[extract_command]
			system(extract_command, chdir: directory_to_unpack_to)
			raise CorruptPackageError if $? != 0
			`"chmod -Rh ugo-w #{directory_to_unpack_to}"` if set_read_only
			#FileUtils.chmod_R("ugo-w",directory_to_unpack_to) if set_read_only
		}
		directory_to_unpack_to
	end

end
