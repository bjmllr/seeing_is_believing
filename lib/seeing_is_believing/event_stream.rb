class SeeingIsBelieving
  # At the binary level, streaming will have to be opted into, b/c you'd need something on the other side that could display it
  # TODO: we'll use eval for now, later just escape \ns
  module EventStream
    module Event
      LineResult       = Struct.new(:type, :line_number, :inspected)
      StdoutResult     = Struct.new(:stdout)
      StderrResult     = Struct.new(:stderr)
      UnrecordedResult = Struct.new(:type, :line_number)
      BugInSiBResult   = Struct.new(:value)
      MaxLineCaptures  = Struct.new(:value)
      Exitstatus       = Struct.new(:value)
      ExceptionResult  = Struct.new(:line_number, :class_name, :message, :backtrace) do
        def initialize
          super -1, '', '', []
        end
      end

    end

    class Consumer
      def initialize(readstream)
        @readstream = readstream
      end

      def call(n=1)
        return event_for @readstream.gets if n == 1
        n.times.map { event_for @readstream.gets }
      end

      private

      def extract_token(line)
        event_name = line[/[^ ]*/]
        line.sub! /[^ ]*\s*/, ''
        event_name
      end

      # for a consideration of many different ways of doing this, see 5633064
      def extract_string(line)
        Marshal.load extract_token(line).unpack('m0').first
      end

      def event_for(line)
        line.chomp!
        event_name = extract_token(line).intern
        case event_name
        when :result
          line_number = extract_token(line).to_i
          type        = extract_token(line).intern
          inspected   = extract_string(line)
          Event::LineResult.new(type, line_number, inspected)
        when :maxed_result
          line_number = extract_token(line).to_i
          type        = extract_token(line).intern
          Event::UnrecordedResult.new(type, line_number)
        when :exception
          case extract_token(line).intern
          when :begin
            @exception = Event::ExceptionResult.new
            call
          when :line_number
            @exception.line_number = extract_token(line).to_i
            call
          when :class_name
            @exception.class_name = extract_string(line)
            call
          when :message
            @exception.message = extract_string(line)
            call
          when :backtrace
            @exception.backtrace << extract_string(line)
            call
          when :end
            @exception
          end
        when :stdout
          Event::StdoutResult.new(extract_string line)
        when :stderr
          Event::StderrResult.new(extract_string line)
        when :bug_in_sib
          Event::BugInSiBResult.new(extract_token(line) == 'true')
        when :max_line_captures
          token = extract_token(line)
          value = token =~ /infinity/i ? Float::INFINITY : token.to_i
          Event::MaxLineCaptures.new(value)
        when :exitstatus
          # TODO: Will this fuck it up if you run `exit true`?
          Event::Exitstatus.new(extract_token(line).to_i)
        else
          raise "IDK what #{event_name.inspect} is!"
        end
      end
    end

    class Publisher
      attr_accessor :exitstatus, :bug_in_sib, :max_line_captures
      attr_accessor :resultstream
      attr_accessor :recorded_results

      def initialize(resultstream)
        self.resultstream      = resultstream
        self.exitstatus        = 0
        self.bug_in_sib        = false
        self.max_line_captures = Float::INFINITY
        self.recorded_results  = Hash.new { |h, line_num| h[line_num] = Hash.new(0) }
      end

      # TODO: delete?
      def bug_in_sib=(bool)
        @bug_in_sib = !!bool
      end

      # for a consideration of many different ways of doing this, see 5633064
      def to_string_token(string)
        [Marshal.dump(string.to_s)].pack('m0')
      end

      # TODO: can record basic object and that shit
      # TODO: only records inspect once
      # TODO: Check whatever else result is currently doing
      def record_result(type, line_number, value)
        count = recorded_results[line_number][type]
        recorded_results[line_number][type] = count + 1
        if count < max_line_captures
          resultstream << "result #{line_number} #{type} #{to_string_token value.inspect}\n"
        elsif count == max_line_captures
          resultstream << "maxed_result #{line_number} #{type}\n"
        end
        value
      end

      def record_exception(line_number, exception)
        resultstream << "exception begin\n"
        resultstream << "exception line_number #{line_number}\n"
        resultstream << "exception class_name  #{to_string_token exception.class.name}\n"
        resultstream << "exception message     #{to_string_token exception.message}\n"
        exception.backtrace.each do |line|
          resultstream << "exception backtrace #{to_string_token line}\n"
        end
        resultstream << "exception end\n"
      end

      # TODO with a mutex, we could also write this dynamically!
      def record_stdout(stdout)
        resultstream << "stdout #{to_string_token stdout}\n"
      end

      def record_stderr(stderr)
        resultstream << "stderr #{to_string_token stderr}\n"
      end

      def finalize
        resultstream << "bug_in_sib #{bug_in_sib}\n"
        resultstream << "max_line_captures #{max_line_captures}\n"
        resultstream << "exitstatus #{exitstatus}\n"
      end
    end
  end
end
