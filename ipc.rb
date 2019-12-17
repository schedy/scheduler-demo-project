require 'set'

module IPC

	class SoftFail < Exception; end

	def self.lockdir(lockname)
		puts 'Lockdir: %s'%[lockname]
		Thread.current[:lockdir] ||= Set.new
		skip_lockdir_creation = Thread.current[:lockdir].include?(lockname)
		do_clean = true
		if skip_lockdir_creation
			puts "Lockdir creation skipped (lock already acquired): "+lockname
			do_clean = false 
		else
			waiting_since = Time.new
			begin
				Dir.mkdir(lockname)
				puts 'Lockdir created (after %is of waiting): %s, %s'%[Time.new-waiting_since, lockname,caller[-1]]
			rescue Errno::EEXIST

				puts 'Lockdir exists, waiting (so far for %is):,%s '%[Time.new-waiting_since, lockname,caller[-1]]  if (Time.new-waiting_since).floor % 10 == 0
				sleep(1)
				retry
			end
			Thread.current[:lockdir] << lockname
		end
		yield
	rescue SoftFail
		if skip_lockdir_creation
			puts 'Lockdir SoftFail (still holding the logs for parent transaction): ' + lockname
		else
			puts 'Lockdir SoftFail: ' + lockname
		end
		raise
	rescue => e
		puts 'Lockdir RETAINED DUE TO HARD FAIL: ' + e.to_s
		do_clean = false
		raise
	ensure
		if do_clean
			Thread.current[:lockdir].delete(lockname) if not skip_lockdir_creation
			Dir.rmdir(lockname)
			puts 'Lockdir removed: ' + lockname
		end
	end

end
