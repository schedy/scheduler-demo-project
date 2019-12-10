class FlashingError < Exception; end
class FatalFlashingError < Exception; end


module SchedyHelper

        ##INFO:
        ##USED IN: scheduler-worker/resources - verifies if jlink flashing has been successful.
	def self.verify_jlink(output)
		# INFO: Raises FlashingError if success or skip messages are not in JLink output to stdout.
		puts "*"*40 + " Begin JLink " + "*"*40
		puts output
		puts "*"*40 + " End JLink " + "*"*40

		success_message = /^(?!\.)O\.K\./m
		skip_message = /Flash download skipped. Flash contents already match/m
		error_message = /Error/
		if  (!(output.match(success_message) or output.match(skip_message)) or (output.match(error_message)))
			raise FlashingError
		else
			puts "Successfully flashed !"
			return true
		end
	end



end
