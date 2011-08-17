require 'strscan'    unless defined?(StringScanner)
require 'bigdecimal' unless defined?(BigDecimal)

module RDF::Turtle
  ##
  # A lexical analyzer for the Turtle 2 grammar.
  #
  # @example Tokenizing a Turtle string
  #   query = "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> ."
  #   lexer = RDF::Turtle::Lexer.tokenize(query)
  #   lexer.each_token do |token|
  #     puts token.inspect
  #   end
  #
  # @example Handling error conditions
  #   begin
  #     RDF::Turtle::Lexer.tokenize(query)
  #   rescue RDF::Turtle::Lexer::Error => error
  #     warn error.inspect
  #   end
  #
  # @see http://dvcs.w3.org/hg/rdf/raw-file/default/rdf-turtle/turtle.bnf
  # @see http://en.wikipedia.org/wiki/Lexical_analysis
  class Lexer
    include Enumerable

    ESCAPE_CHARS         = {
      '\t'   => "\t",    # \u0009 (tab)
      '\n'   => "\n",    # \u000A (line feed)
      '\r'   => "\r",    # \u000D (carriage return)
      '\b'   => "\b",    # \u0008 (backspace)
      '\f'   => "\f",    # \u000C (form feed)
      '\\"'  => '"',     # \u0022 (quotation mark, double quote mark)
      '\\\'' => '\'',    # \u0027 (apostrophe-quote, single quote mark)
      '\\\\' => '\\'     # \u005C (backslash)
    }
    ESCAPE_CHAR4         = /\\u([0-9A-Fa-f]{4,4})/                              # \uXXXX
    ESCAPE_CHAR8         = /\\U([0-9A-Fa-f]{8,8})/                              # \UXXXXXXXX
    ESCAPE_CHAR          = /#{ESCAPE_CHAR4}|#{ESCAPE_CHAR8}/

    if RUBY_VERSION >= '1.9'
      ##
      # Unicode regular expressions for Ruby 1.9+ with the Oniguruma engine.
      U_CHARS1         = Regexp.compile(<<-EOS.gsub(/\s+/, ''))
                           [\\u00C0-\\u00D6]|[\\u00D8-\\u00F6]|[\\u00F8-\\u02FF]|
                           [\\u0370-\\u037D]|[\\u037F-\\u1FFF]|[\\u200C-\\u200D]|
                           [\\u2070-\\u218F]|[\\u2C00-\\u2FEF]|[\\u3001-\\uD7FF]|
                           [\\uF900-\\uFDCF]|[\\uFDF0-\\uFFFD]|[\\u{10000}-\\u{EFFFF}]
                         EOS
      U_CHARS2         = Regexp.compile("\\u00B7|[\\u0300-\\u036F]|[\\u203F-\\u2040]")
    else
      ##
      # UTF-8 regular expressions for Ruby 1.8.x.
      U_CHARS1         = Regexp.compile(<<-EOS.gsub(/\s+/, ''))
                           \\xC3[\\x80-\\x96]|                                (?# [\\u00C0-\\u00D6]|)
                           \\xC3[\\x98-\\xB6]|                                (?# [\\u00D8-\\u00F6]|)
                           \\xC3[\\xB8-\\xBF]|[\\xC4-\\xCB][\\x80-\\xBF]|     (?# [\\u00F8-\\u02FF]|)
                           \\xCD[\\xB0-\\xBD]|                                (?# [\\u0370-\\u037D]|)
                           \\xCD\\xBF|[\\xCE-\\xDF][\\x80-\\xBF]|             (?# [\\u037F-\\u1FFF]|)
                           \\xE0[\\xA0-\\xBF][\\x80-\\xBF]|                   (?# ...)
                           \\xE1[\\x80-\\xBF][\\x80-\\xBF]|                   (?# ...)
                           \\xE2\\x80[\\x8C-\\x8D]|                           (?# [\\u200C-\\u200D]|)
                           \\xE2\\x81[\\xB0-\\xBF]|                           (?# [\\u2070-\\u218F]|)
                           \\xE2[\\x82-\\x85][\\x80-\\xBF]|                   (?# ...)
                           \\xE2\\x86[\\x80-\\x8F]|                           (?# ...)
                           \\xE2[\\xB0-\\xBE][\\x80-\\xBF]|                   (?# [\\u2C00-\\u2FEF]|)
                           \\xE2\\xBF[\\x80-\\xAF]|                           (?# ...)
                           \\xE3\\x80[\\x81-\\xBF]|                           (?# [\\u3001-\\uD7FF]|)
                           \\xE3[\\x81-\\xBF][\\x80-\\xBF]|                   (?# ...)
                           [\\xE4-\\xEC][\\x80-\\xBF][\\x80-\\xBF]|           (?# ...)
                           \\xED[\\x80-\\x9F][\\x80-\\xBF]|                   (?# ...)
                           \\xEF[\\xA4-\\xB6][\\x80-\\xBF]|                   (?# [\\uF900-\\uFDCF]|)
                           \\xEF\\xB7[\\x80-\\x8F]|                           (?# ...)
                           \\xEF\\xB7[\\xB0-\\xBF]|                           (?# [\\uFDF0-\\uFFFD]|)
                           \\xEF[\\xB8-\\xBE][\\x80-\\xBF]|                   (?# ...)
                           \\xEF\\xBF[\\x80-\\xBD]|                           (?# ...)
                           \\xF0[\\x90-\\xBF][\\x80-\\xBF][\\x80-\\xBF]|      (?# [\\u{10000}-\\u{EFFFF}])
                           [\\xF1-\\xF2][\\x80-\\xBF][\\x80-\\xBF][\\x80-\\xBF]|
                           \\xF3[\\x80-\\xAF][\\x80-\\xBF][\\x80-\\xBF]       (?# ...)
                         EOS
      U_CHARS2         = Regexp.compile(<<-EOS.gsub(/\s+/, ''))
                           \\xC2\\xB7|                                        (?# \\u00B7|)
                           \\xCC[\\x80-\\xBF]|\\xCD[\\x80-\\xAF]|             (?# [\\u0300-\\u036F]|)
                           \\xE2\\x80\\xBF|\\xE2\\x81\\x80                    (?# [\\u203F-\\u2040])
                         EOS
    end

    KEYWORD              = /#{KEYWORDS.join('|')}/i                             # [17] & [18]
    DELIMITER            = /\^\^|[()\[\],;\.]/
    OPERATOR             = /a|[<>+\-*\/]/
    COMMENT              = /#.*/

    PN_CHARS_BASE        = /[A-Z]|[a-z]|#{U_CHARS1}/                            # [95s]
    PN_CHARS_U           = /_|#{PN_CHARS_BASE}/                                 # [96s]
    PN_CHARS             = /-|[0-9]|#{PN_CHARS_U}|#{U_CHARS2}/                  # [98s]
    PN_CHARS_BODY        = /(?:(?:\.|#{PN_CHARS})*#{PN_CHARS})?/
    PN_PREFIX            = /#{PN_CHARS_BASE}#{PN_CHARS_BODY}/                   # [99s]
    PN_LOCAL             = /(?:[0-9]|#{PN_CHARS_U})#{PN_CHARS_BODY}/            # [100s]

    IRI_REF              = /<([^<>"{}|^`\\\x00-\x20]*)>/                        # [70s]
    PNAME_NS             = /(#{PN_PREFIX}?):/                                   # [71s]
    PNAME_LN             = /#{PNAME_NS}(#{PN_LOCAL})/                           # [72s]
    BLANK_NODE_LABEL     = /_:(#{PN_LOCAL})/                                    # [73s]
    LANGTAG              = /@([a-zA-Z]+(?:-[a-zA-Z0-9]+)*)/                     # [76s]
    INTEGER              = /[0-9]+/                                             # [77s]
    DECIMAL              = /(?:[0-9]+\.[0-9]*|\.[0-9]+)/                        # [78s]
    EXPONENT             = /[eE][+-]?[0-9]+/                                    # [86s]
    DOUBLE               = /(?:[0-9]+\.[0-9]*|\.[0-9]+|[0-9]+)#{EXPONENT}/      # [79s]
    ECHAR                = /\\[tbnrf\\"']/                                      # [91s]
    STRING_LITERAL1      = /'((?:[^\x27\x5C\x0A\x0D]|#{ECHAR})*)'/              # [87s]
    STRING_LITERAL2      = /"((?:[^\x22\x5C\x0A\x0D]|#{ECHAR})*)"/              # [88s]
    STRING_LITERAL_LONG1 = /'''((?:(?:'|'')?(?:[^'\\]|#{ECHAR})+)*)'''/m        # [89s]
    STRING_LITERAL_LONG2 = /"""((?:(?:"|"")?(?:[^"\\]|#{ECHAR})+)*)"""/m        # [90s]
    WS                   = /\x20|\x09|\x0D|\x0A/                                # [93s]
    NIL                  = /\(#{WS}*\)/                                         # [92s]
    ANON                 = /\[#{WS}*\]/                                         # [94s]

    BooleanLiteral       = /true|false/                                         # [65s]
    String               = /#{STRING_LITERAL_LONG1}|#{STRING_LITERAL_LONG2}|
                            #{STRING_LITERAL1}|#{STRING_LITERAL2}/x             # [66s]

    # Make all defined regular expression constants immutable:
    constants.each { |name| const_get(name).freeze }

    ##
    # Returns a copy of the given `input` string with all `\uXXXX` and
    # `\UXXXXXXXX` Unicode codepoint escape sequences replaced with their
    # unescaped UTF-8 character counterparts.
    #
    # @param  [String] input
    # @return [String]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#codepointEscape
    def self.unescape_codepoints(input)
      string = input.dup
      string.force_encoding(Encoding::ASCII_8BIT) if string.respond_to?(:force_encoding) # Ruby 1.9+

      # Decode \uXXXX and \UXXXXXXXX code points:
      string.gsub!(ESCAPE_CHAR) do
        s = [($1 || $2).hex].pack('U*')
        s.respond_to?(:force_encoding) ? s.force_encoding(Encoding::ASCII_8BIT) : s
      end

      string.force_encoding(Encoding::UTF_8) if string.respond_to?(:force_encoding)      # Ruby 1.9+
      string
    end

    ##
    # Returns a copy of the given `input` string with all string escape
    # sequences (e.g. `\n` and `\t`) replaced with their unescaped UTF-8
    # character counterparts.
    #
    # @param  [String] input
    # @return [String]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#grammarEscapes
    def self.unescape_string(input)
      input.gsub(ECHAR) { |escaped| ESCAPE_CHARS[escaped] }
    end

    ##
    # Tokenizes the given `input` string or stream.
    #
    # @param  [String, #to_s]          input
    # @param  [Hash{Symbol => Object}] options
    # @yield  [lexer]
    # @yieldparam [Lexer] lexer
    # @return [Lexer]
    # @raise  [Lexer::Error] on invalid input
    def self.tokenize(input, options = {}, &block)
      lexer = self.new(input, options)
      block_given? ? block.call(lexer) : lexer
    end

    ##
    # Initializes a new lexer instance.
    #
    # @param  [String, #to_s]          input
    # @param  [Hash{Symbol => Object}] options
    def initialize(input = nil, options = {})
      @options = options.dup
      self.input = input if input
    end

    ##
    # Any additional options for the lexer.
    #
    # @return [Hash]
    attr_reader   :options

    ##
    # The current input string being processed.
    #
    # @return [String]
    attr_accessor :input

    ##
    # The current line number (zero-based).
    #
    # @return [Integer]
    attr_reader   :lineno

    ##
    # @param  [String, #to_s] input
    # @return [void]
    def input=(input)
      @input = case input
        when ::String     then input
        when IO, StringIO then input.read
        else input.to_s
      end
      @input = self.class.unescape_codepoints(@input) if ESCAPE_CHAR === @input
      @lineno = 1
      @scanner = StringScanner.new(@input)
    end

    ##
    # Returns `true` if the input string is lexically valid.
    #
    # To be considered valid, the input string must contain more than zero
    # tokens, and must not contain any invalid tokens.
    #
    # @return [Boolean]
    def valid?
      begin
        !count.zero?
      rescue Error
        false
      end
    end

    ##
    # Enumerates each token in the input string.
    #
    # @yield  [token]
    # @yieldparam [Token] token
    # @return [Enumerator]
    def each_token(&block)
      if block_given?
        while token = shift
          yield token
        end
      end
      enum_for(:each_token)
    end
    alias_method :each, :each_token

    ##
    # Returns first token in input stream
    #
    # @return [Token]
    def first
      return nil unless scanner

      if @first.nil?
        {} while !scanner.eos? && (skip_whitespace || skip_comment)
        return @scanner = nil if scanner.eos?

        @first = match_token
        
        if @first.nil?
          lexme = (@scanner.rest.split(/#{WS}|#{COMMENT}/).first rescue nil) || @scanner.rest
          raise Error.new("Invalid token #{lexme.inspect} on line #{lineno + 1}",
            :input => input, :token => lexme, :lineno => lineno)
        end
      end

      @first
    end

    ##
    # Returns current token and shifts to next
    #
    # @return [Token]
    def shift
      cur = first
      @first = nil
      cur
    end
    
  protected

    # @return [StringScanner]
    attr_reader :scanner

    # @see http://www.w3.org/TR/rdf-sparql-query/#whitespace
    def skip_whitespace
      # skip all white space, but keep track of the current line number
      if matched = scanner.scan(WS)
        @lineno += matched.count("\n")
        matched
      end
    end

    # @see http://www.w3.org/TR/rdf-sparql-query/#grammarComments
    def skip_comment
      # skip the remainder of the current line
      skipped = scanner.skip(COMMENT)
    end

    def match_token
      match_iri_ref         ||
      match_pname_ln        ||
      match_pname_ns        ||
      match_string_long_1   ||
      match_string_long_2   ||
      match_string_1        ||
      match_string_2        ||
      match_keyword         ||
      match_langtag         ||
      match_double          ||
      match_decimal         ||
      match_integer         ||
      match_boolean_literal ||
      match_blank_node_label||
      match_nil             ||
      match_anon            ||
      match_delimiter       ||
      match_operator
    end

    def match_var1
      if matched = scanner.scan(VAR1)
        token(:VAR1, scanner[1].to_s)
      end
    end

    def match_var2
      if matched = scanner.scan(VAR2)
        token(:VAR2, scanner[1].to_s)
      end
    end

    def match_iri_ref
      if matched = scanner.scan(IRI_REF)
        token(:IRI_REF, scanner[1].to_s)
      end
    end

    def match_pname_ln
      if matched = scanner.scan(PNAME_LN)
        token(:PNAME_LN, [scanner[1].empty? ? nil : scanner[1].to_s, scanner[2].to_s])
      end
    end

    def match_pname_ns
      if matched = scanner.scan(PNAME_NS)
        token(:PNAME_NS, scanner[1].empty? ? nil : scanner[1].to_s)
      end
    end

    def match_string_long_1
      if matched = scanner.scan(STRING_LITERAL_LONG1)
        token(:STRING_LITERAL_LONG1, self.class.unescape_string(scanner[1]))
      end
    end

    def match_string_long_2
      if matched = scanner.scan(STRING_LITERAL_LONG2)
        token(:STRING_LITERAL_LONG2, self.class.unescape_string(scanner[1]))
      end
    end

    def match_string_1
      if matched = scanner.scan(STRING_LITERAL1)
        token(:STRING_LITERAL1, self.class.unescape_string(scanner[1]))
      end
    end

    def match_string_2
      if matched = scanner.scan(STRING_LITERAL2)
        token(:STRING_LITERAL2, self.class.unescape_string(scanner[1]))
      end
    end

    def match_langtag
      if matched = scanner.scan(LANGTAG)
        token(:LANGTAG, scanner[1].to_s)
      end
    end

    def match_double
      if matched = scanner.scan(DOUBLE)
        token(:DOUBLE, matched)
      end
    end

    def match_decimal
      if matched = scanner.scan(DECIMAL)
        token(:DECIMAL, matched)
      end
    end

    def match_integer
      if matched = scanner.scan(INTEGER)
        token(:INTEGER, matched)
      end
    end

    def match_boolean_literal
      if matched = scanner.scan(BooleanLiteral)
        token(:BooleanLiteral, matched)
      end
    end

    def match_blank_node_label
      if matched = scanner.scan(BLANK_NODE_LABEL)
        token(:BLANK_NODE_LABEL, scanner[1].to_s)
      end
    end

    def match_nil
      if matched = scanner.scan(NIL)
        token(:NIL)
      end
    end

    def match_anon
      if matched = scanner.scan(ANON)
        token(:ANON)
      end
    end

    def match_keyword
      if matched = scanner.scan(KEYWORD)
        token(nil, matched.to_s)
      end
    end

    def match_delimiter
      if matched = scanner.scan(DELIMITER)
        token(nil, matched.to_s)
      end
    end

    def match_operator
      if matched = scanner.scan(OPERATOR)
        token(nil, matched.to_s)
      end
    end

  protected

    ##
    # Constructs a new token object annotated with the current line number.
    #
    # The parser relies on the type being a symbolized URI and the value being
    # a string, if there is no type. If there is a type, then the value takes
    # on the native representation appropriate for that type.
    #
    # @param  [Symbol] type
    # @param  [Object] value
    # @return [Token]
    def token(type, value = nil)
      Token.new(type, value, :lineno => lineno)
    end

    ##
    # Represents a lexer token.
    #
    # @example Creating a new token
    #   token = SPARQL::Grammar::Lexer::Token.new(:LANGTAG, :en)
    #   token.type   #=> :LANGTAG
    #   token.value  #=> "en"
    #
    # @see http://en.wikipedia.org/wiki/Lexical_analysis#Token
    class Token
      ##
      # Initializes a new token instance.
      #
      # @param  [Symbol]                 type
      # @param  [Object]                 value
      # @param  [Hash{Symbol => Object}] options
      # @option options [Integer]        :lineno (nil)
      def initialize(type, value = nil, options = {})
        @type, @value = (type ? type.to_s.to_sym : nil), value
        @options = options.dup
        @lineno  = @options.delete(:lineno)
      end

      ##
      # The token's symbol type.
      #
      # @return [Symbol]
      attr_reader :type

      ##
      # The token's value.
      #
      # @return [Object]
      attr_reader :value

      ##
      # The line number where the token was encountered.
      #
      # @return [Integer]
      attr_reader :lineno

      ##
      # Any additional options for the token.
      #
      # @return [Hash]
      attr_reader :options

      ##
      # Returns the attribute named by `key`.
      #
      # @param  [Symbol] key
      # @return [Object]
      def [](key)
        key = key.to_s.to_sym unless key.is_a?(Integer) || key.is_a?(Symbol)
        case key
          when 0, :type  then @type
          when 1, :value then @value
          else nil
        end
      end

      ##
      # Returns `true` if the given `value` matches either the type or value
      # of this token.
      #
      # @example Matching using the symbolic type
      #   SPARQL::Grammar::Lexer::Token.new(:NIL) === :NIL     #=> true
      #
      # @example Matching using the string value
      #   SPARQL::Grammar::Lexer::Token.new(nil, "{") === "{"  #=> true
      #
      # @param  [Symbol, String] value
      # @return [Boolean]
      def ===(value)
        case value
          when Symbol   then value == @type
          when ::String then value.to_s == @value.to_s
          else value == @value
        end
      end

      ##
      # Returns a hash table representation of this token.
      #
      # @return [Hash]
      def to_hash
        {:type => @type, :value => @value}
      end
      
      ##
      # Readable version of token
      def to_s
        @type ? @type.inspect : @value
      end

      ##
      # Returns type, if not nil, otherwise value
      def representation
        @type ? @type : @value
      end

      ##
      # Returns an array representation of this token.
      #
      # @return [Array]
      def to_a
        [@type, @value]
      end

      ##
      # Returns a developer-friendly representation of this token.
      #
      # @return [String]
      def inspect
        to_hash.inspect
      end
    end # class Token

    ##
    # Raised for errors during lexical analysis.
    #
    # @example Raising a lexer error
    #   raise SPARQL::Grammar::Lexer::Error.new(
    #     "invalid token '%' on line 10",
    #     :input => query, :token => '%', :lineno => 9)
    #
    # @see http://ruby-doc.org/core/classes/StandardError.html
    class Error < StandardError
      ##
      # The input string associated with the error.
      #
      # @return [String]
      attr_reader :input

      ##
      # The invalid token which triggered the error.
      #
      # @return [String]
      attr_reader :token

      ##
      # The line number where the error occurred.
      #
      # @return [Integer]
      attr_reader :lineno

      ##
      # Initializes a new lexer error instance.
      #
      # @param  [String, #to_s]          message
      # @param  [Hash{Symbol => Object}] options
      # @option options [String]         :input  (nil)
      # @option options [String]         :token  (nil)
      # @option options [Integer]        :lineno (nil)
      def initialize(message, options = {})
        @input  = options[:input]
        @token  = options[:token]
        @lineno = options[:lineno]
        super(message.to_s)
      end
    end # class Error
  end # class Lexer
end # module RDF::Turtle
