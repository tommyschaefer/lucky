module Lucky::TextHelpers
  @@_cycles = Hash(String, Cycle).new

  def truncate(text : String, length : Int32 = 30, omission : String = "...", separator : String | Nil = nil, escape : Bool = false, blk : Nil | Proc = nil)
    if text
      content = truncate_text(text, length, omission, separator)
      raw (escape ? HTML.escape(content) : content)
      blk.call if !blk.nil? && text.size > length
      @view
    end
  end

  def truncate(text : String, length : Int32 = 30, omission : String = "...", separator : String | Nil = nil, escape : Bool = true, &block : -> _)
    truncate(text, length, omission, separator, escape, blk: block)
  end

  private def truncate_text(text : String, truncate_at : Int32, omission : String = "...", separator : String | Nil = nil)
    return text unless text.size > truncate_at

    length_with_room_for_omission = truncate_at - omission.size
    stop = \
       if separator
         text.rindex(separator, length_with_room_for_omission) || length_with_room_for_omission
       else
         length_with_room_for_omission
       end

    "#{text[0, stop]}#{omission}"
  end

  def highlight(text : String, phrases : Array(String | Regex), highlighter : Proc | String = "<mark>\\1</mark>")
    if text.blank? || phrases.all?(&.to_s.blank?)
      raw (text || "")
    else
      match = phrases.map do |p|
        p.is_a?(Regex) ? p.to_s : Regex.escape(p.to_s)
      end.join("|")

      if highlighter.is_a?(Proc)
        raw text.gsub(/(#{match})(?![^<]*?>)/i, &highlighter)
      else
        raw text.gsub(/(#{match})(?![^<]*?>)/i, highlighter)
      end
    end
  end

  def highlight(text : String, phrases : Array(String | Regex), &block : String -> _)
    highlight(text, phrases, highlighter: block)
  end

  def highlight(text : String, phrase : String | Regex, highlighter : Proc | String = "<mark>\\1</mark>")
    phrases = [phrase] of String | Regex
    highlight(text, phrases, highlighter: highlighter)
  end

  def highlight(text : String, phrase : String | Regex, &block : String -> _)
    phrases = [phrase] of String | Regex
    highlight(text, phrases, highlighter: block)
  end

  def excerpt(text : String, phrase : Regex | String, separator : String = "", radius : Int32 = 100, omission : String = "...")
    return "" if text.to_s.blank?

    case phrase
    when Regex
      regex = phrase
    else
      regex = /#{Regex.escape(phrase.to_s)}/i
    end

    return unless matches = text.match(regex)
    phrase = matches[0]

    unless separator.empty?
      text.split(separator).each do |value|
        if value.match(regex)
          phrase = value
          break
        end
      end
    end

    first_part, second_part = text.split(phrase, 2)

    prefix, first_part = cut_excerpt_part(:first, first_part, separator, radius, omission)
    postfix, second_part = cut_excerpt_part(:second, second_part, separator, radius, omission)

    affix = [first_part, separator, phrase, separator, second_part].join.strip
    raw [prefix, affix, postfix].join
  end

  def pluralize(count : Int32 | String | Nil, singular : String, plural = nil)
    word = if (count == 1 || count =~ /^1(\.0+)?$/)
             singular
           else
             plural || LuckyInflector::Inflector.pluralize(singular)
           end

    raw "#{count || 0} #{word}"
  end

  def word_wrap(text : String, line_width : Int32 = 80, break_sequence : String = "\n")
    text = text.split("\n").map do |line|
      line.size > line_width ? line.gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1#{break_sequence}").strip : line
    end
    raw text.join(break_sequence)
  end

  def simple_format(text : String, &block : String -> _)
    paragraphs = split_paragraphs(text)

    paragraphs = [""] if paragraphs.empty?

    paragraphs.each do |paragraph|
      yield paragraph
      raw "\n\n" unless paragraph == paragraphs.last
    end
    @view
  end

  def simple_format(text : String, **html_options)
    simple_format(text) do |formatted_text|
      para(html_options) do
        raw formatted_text
      end
    end
  end

  # Creates a comma-separated sentence from the provided `Enumerable` *list*
  # and appends it to the view.
  #
  # #### Options:
  #
  # The following options allow you to specify how the sentence is constructed:
  #   - *word_connector* - A string used to join the elements in *list*s
  # containing three or more elements (Default is ", ")
  #   - *two_word_connector* - A string used to join the elements in *list*s
  # containing exactly two elements (Default is " and ")
  #   - *last_word_connector* - A string used to join the last element in
  # *list*s containing three or more elements (Default is ", and ")
  #
  # #### Examples:
  #
  #     to_sentence([] of String)            # => ""
  #     to_sentence([1])                     # => "1"
  #     to_sentence(["one", "two"])          # => "one and two"
  #     to_sentence({"one", "two", "three"}) # => "one, two, and three"
  #
  #     to_sentence(["one", "two", "three"], word_connector: " + ")
  #     # => one + two, and three
  #
  #     to_sentence(Set{"a", "z"}, two_word_connector: " to ")
  #     # => a to z
  #
  #     to_sentence(1..3, last_word_connector: ", or ")
  #     # => 1, 2, or 3
  #
  # NOTE: By default `#to_sentence` will include a
  # [serial comma](https://en.wikipedia.org/wiki/Serial_comma). This can be
  # overriden like so:
  #
  #     to_sentence(["one", "two", "three"], last_word_connector: " and ")
  #     # => one, two and thre
  def to_sentence(list : Enumerable,
                  word_connector : String = ", ",
                  two_word_connector : String = " and ",
                  last_word_connector : String = ", and ")
    list = list.to_a

    if list.size < 3
      return text list.join(two_word_connector)
    end

    text "#{list[0..-2].join(word_connector)}#{last_word_connector}#{list.last}"
  end

  private def normalize_values(values)
    string_values = Array(String).new
    values.each { |v| string_values << v.to_s }
    values = string_values
  end

  def cycle(values : Array, name = "default")
    values = normalize_values(values)
    cycle = get_cycle(name)
    unless cycle && cycle.values == values
      cycle = set_cycle(name, Cycle.new(values))
    end
    raw cycle.to_s
  end

  def cycle(*values, name : String = "default")
    values = normalize_values(values)
    cycle(values, name: name)
  end

  def current_cycle(name : String = "default")
    cycle = get_cycle(name)
    cycle.current_value if cycle
  end

  def reset_cycle(name : String = "default")
    cycle = get_cycle(name)
    cycle.reset if cycle
  end

  class Cycle
    @values : Array(String)
    getter :values
    @index = 0

    def initialize(*values)
      string_values = Array(String).new
      values.each { |v| string_values << v.to_s }
      @values = string_values
      reset
    end

    def initialize(values : Array(String))
      @values = Array(String).new
      @values = values
      reset
    end

    def reset
      @index = 0
    end

    def current_value
      @values[previous_index]?.to_s
    end

    def to_s
      value = @values[@index]?.to_s
      @index = next_index
      value
    end

    private def next_index
      step_index(1)
    end

    private def previous_index
      step_index(-1)
    end

    private def step_index(n : Int32)
      (@index + n) % @values.size
    end
  end

  def reset_cycles
    @@_cycles = Hash(String, Cycle).new
  end

  private def get_cycle(name : String)
    @@_cycles[name]?
  end

  private def set_cycle(name : String, cycle_object : Cycle)
    @@_cycles[name] = cycle_object
  end

  private def cut_excerpt_part(part_position : Symbol, part : String | Nil, separator : String, radius : Int32, omission : String)
    return "", "" if part.nil?

    part = part.split(separator)
    part.delete("")
    affix = part.size > radius ? omission : ""

    part = if part_position == :first
             drop_index = [part.size - radius, 0].max
             part[drop_index..-1]
           else
             part.first(radius)
           end

    return affix, part.join(separator)
  end

  private def split_paragraphs(text : String)
    return Array(String).new if text.blank?

    text.to_s.gsub(/\r\n?/, "\n").split(/\n\n+/).map do |t|
      t.gsub(/([^\n]\n)(?=[^\n])/, "\\1<br />") || t
    end
  end
end
