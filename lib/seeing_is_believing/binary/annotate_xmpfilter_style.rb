class SeeingIsBelieving
  class Binary
    class AnnotateXmpfilterStyle
      def self.prepare_body(uncleaned_body)
        require 'seeing_is_believing/binary/remove_annotations'
        RemoveAnnotations.call uncleaned_body, false
      end

      def self.expression_wrapper
        -> program, number_of_captures {
          require 'seeing_is_believing/binary/find_comments'
          inspect_linenos = []
          pp_linenos      = []
          FindComments.new(program).comments.each do |c|
            next if c.comment !~ VALUE_REGEX
            c.preceding_code.empty? ? pp_linenos      << c.line_number - 1
                                    : inspect_linenos << c.line_number
          end

          InspectExpressions.call program,
                                  number_of_captures,
                                  before_all: -> {
                                    # TODO: this is duplicated with the InspectExpressions class
                                    number_of_captures_as_str = number_of_captures.inspect
                                    number_of_captures_as_str = 'Float::INFINITY' if number_of_captures == Float::INFINITY
                                    "begin; require 'pp'; $SiB.max_line_captures = #{number_of_captures_as_str}; $SiB.num_lines = #{program.lines.count}; "
                                  },
                                  after_each: -> line_number {
                                    should_inspect = inspect_linenos.include?(line_number)
                                    should_pp      = pp_linenos.include?(line_number)
                                    inspect        = "$SiB.record_result(:inspect, #{line_number}, v)"
                                    pp             = "$SiB.record_result(:pp, #{line_number}, v) { PP.pp v, '', 74 }" # TODO: Is 74 the right value? Prob not, I think it's 80(default width) - 1(comment width) - 5(" => {"), but if I allow indented `# => `, then that would need to be less than 74 (idk if I actually do this or not, though :P)

                                    if    should_inspect && should_pp then ").tap { |v| #{inspect}; #{pp} }"
                                    elsif should_inspect              then ").tap { |v| #{inspect} }"
                                    elsif should_pp                   then ").tap { |v| #{pp} }"
                                    else                                   ")"
                                    end
                                  }
        }
      end

      def initialize(body, results, options={})
        @options = options
        @body    = body
        @results = results
      end

      # TODO: I think that this should respect the alignment strategy
      # and we should just add a new alignment strategy for default xmpfilter style
      def call
        @new_body ||= begin
          # TODO: doesn't currently realign output markers, do we want to do that?
          require 'seeing_is_believing/binary' # defines the markers
          require 'seeing_is_believing/binary/rewrite_comments'
          require 'seeing_is_believing/binary/comment_formatter'
          new_body = RewriteComments.call @body do |line_number, preceding_code, whitespace, comment|
            if !comment[VALUE_REGEX]
              [whitespace, comment]
            elsif preceding_code.empty?
              # TODO: check that having multiple mult-line output values here looks good (e.g. avdi's example in a loop)
              pp_value_marker = VALUE_MARKER.sub(/(?<=#).*$/) { |after_comment| ' ' * after_comment.size }
              result          = @results[line_number-1, :pp].map { |result| result.chomp }.join(', ')
              comment_lines   = result.each_line.map.with_index do |comment_line, result_offest|
                if result_offest == 0
                  CommentFormatter.call(preceding_code.size, VALUE_MARKER, comment_line.chomp, @options)
                else
                  CommentFormatter.call(preceding_code.size, pp_value_marker, comment_line.chomp, @options)
                end
              end
              [whitespace, comment_lines.join("\n")]
            else
              result = @results[line_number].map { |result| result.gsub "\n", '\n' }.join(', ')
              [whitespace, CommentFormatter.call(preceding_code.size + whitespace.size, VALUE_MARKER, result, @options)]
            end
          end

          require 'seeing_is_believing/binary/annotate_end_of_file'
          AnnotateEndOfFile.add_stdout_stderr_and_exceptions_to new_body, @results, @options

          # What's w/ this debugger? maybe this should move higher?
          @options[:debugger].context "OUTPUT"
          new_body
        end
      end
    end
  end
end
