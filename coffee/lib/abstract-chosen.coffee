root = this

class AbstractChosen

  constructor: (@form_field, @options={}) ->
    return unless AbstractChosen.browser_is_supported()
    @is_multiple = @form_field.multiple
    this.set_default_text()
    this.set_default_values()

    this.setup()

    this.set_up_html()
    this.register_observers()

    this.finish_setup()

  set_default_values: ->
    @click_test_action = (evt) => this.test_active_click(evt)
    @activate_action = (evt) => this.activate_field(evt)
    @active_field = false
    @mouse_on_container = false
    @results_showing = false
    @result_highlighted = null
    @result_single_selected = null
    @allow_single_deselect = if @options.allow_single_deselect? and @form_field.options[0]? and @form_field.options[0].text is "" then @options.allow_single_deselect else false
    @disable_search_threshold = @options.disable_search_threshold || 0
    @disable_search = @options.disable_search || false
    @enable_split_word_search = if @options.enable_split_word_search? then @options.enable_split_word_search else true
    @group_search = if @options.group_search? then @options.group_search else true
    @search_contains = @options.search_contains || false
    @single_backstroke_delete = @options.single_backstroke_delete || false
    @max_selected_options = @options.max_selected_options || Infinity
    @inherit_select_classes = @options.inherit_select_classes || false

  set_default_text: ->
    if @form_field.getAttribute("data-placeholder")
      @default_text = @form_field.getAttribute("data-placeholder")
    else if @is_multiple
      @default_text = @options.placeholder_text_multiple || @options.placeholder_text || AbstractChosen.default_multiple_text
    else
      @default_text = @options.placeholder_text_single || @options.placeholder_text || AbstractChosen.default_single_text

    @results_none_found = @form_field.getAttribute("data-no_results_text") || @options.no_results_text || AbstractChosen.default_no_result_text

  mouse_enter: -> @mouse_on_container = true
  mouse_leave: -> @mouse_on_container = false

  input_focus: (evt) ->
    if @is_multiple
      setTimeout (=> this.container_mousedown()), 50 unless @active_field
    else
      @activate_field() unless @active_field

  input_blur: (evt) ->
    if not @mouse_on_container
      @active_field = false
      setTimeout (=> this.blur_test()), 100

  results_option_build: (options) ->
    content = ''
    for data in @results_data
      if data.group && (data.search_match || data.group_match)
        content += this.result_add_group data
      else if !data.empty && data.search_match
        content += this.result_add_option data

      # this select logic pins on an awkward flag
      # we can make it better
      if options?.first
        if data.selected and @is_multiple
          this.choice_build data
        else if data.selected and not @is_multiple
          this.single_set_selected_text(data.text)

    content

  result_add_option: (option) ->
    option.dom_id = @container_id + "_o_" + option.array_index

    classes = []
    classes.push "active-result" if !option.disabled and !(option.selected and @is_multiple)
    classes.push "disabled-result" if option.disabled and !(option.selected and @is_multiple)
    classes.push "result-selected" if option.selected
    classes.push "group-option" if option.group_array_index?
    classes.push option.classes if option.classes != ""

    style = if option.style.cssText != "" then " style=\"#{option.style}\"" else ""

    """<li id="#{option.dom_id}" class="#{classes.join(' ')}"#{style}>#{option.search_text}</li>"""

  result_add_group: (group) ->
    group.dom_id = @container_id + "_g_" + group.array_index
    """<li id="#{group.dom_id}" class="group-result">#{group.search_text}</li>"""

  results_update_field: ->
    this.set_default_text()
    this.results_reset_cleanup() if not @is_multiple
    this.result_clear_highlight()
    @result_single_selected = null
    this.results_build()

  results_toggle: ->
    if @results_showing
      this.results_hide()
    else
      this.results_show()

  results_search: (evt) ->
    if @results_showing
      this.winnow_results()
    else
      this.results_show()

  winnow_results: ->
    this.no_results_clear()

    results = 0

    searchText = this.get_search_text()
    regexAnchor = if @search_contains then "" else "^"
    regex = new RegExp(regexAnchor + searchText.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&"), 'i')
    zregex = new RegExp(searchText.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&"), 'i')

    for option in @results_data
      if not option.empty

        option.group_match = false if option.group

        unless option.group and not @group_search
          option.search_match = false

          option.search_text = if option.group then option.label else option.html
          option.search_match = this.search_string_match(option.search_text, regex)
          results += 1 if option.search_match

          if option.search_match
            if searchText.length
              startpos = option.search_text.search zregex
              text = option.search_text.substr(0, startpos + searchText.length) + '</em>' + option.search_text.substr(startpos + searchText.length)
              option.search_text = text.substr(0, startpos) + '<em>' + text.substr(startpos)

            @results_data[option.group_array_index].group_match = true if option.group_array_index?
          
          else if option.group_array_index? and @results_data[option.group_array_index].search_match
            option.search_match = true

    if results < 1 and searchText.length
      this.update_results_content ""
      this.no_results searchText
    else
      this.update_results_content this.results_option_build()
      this.winnow_results_set_highlight()

  search_string_match: (search_string, regex) ->
    if regex.test search_string
      return true
    else if @enable_split_word_search and (search_string.indexOf(" ") >= 0 or search_string.indexOf("[") == 0)
      #TODO: replace this substitution of /\[\]/ with a list of characters to skip.
      parts = search_string.replace(/\[|\]/g, "").split(" ")
      if parts.length
        for part in parts
          if regex.test part
            return true

  choices_count: ->
    return @selected_option_count if @selected_option_count?

    @selected_option_count = 0
    for option in @form_field.options
      @selected_option_count += 1 if option.selected
    
    return @selected_option_count

  choices_click: (evt) ->
    evt.preventDefault()
    this.results_show() unless @results_showing or @is_disabled

  keyup_checker: (evt) ->
    stroke = evt.which ? evt.keyCode
    this.search_field_scale()

    switch stroke
      when 8
        if @is_multiple and @backstroke_length < 1 and this.choices_count() > 0
          this.keydown_backstroke()
        else if not @pending_backstroke
          this.result_clear_highlight()
          this.results_search()
      when 13
        evt.preventDefault()
        this.result_select(evt) if this.results_showing
      when 27
        this.results_hide() if @results_showing
        return true
      when 9, 38, 40, 16, 91, 17
        # don't do anything on these keys
      else this.results_search()

  generate_field_id: ->
    new_id = this.generate_random_id()
    @form_field.id = new_id
    new_id

  generate_random_char: ->
    chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    rand = Math.floor(Math.random() * chars.length)
    newchar = chars.substring rand, rand+1

  container_width: ->
    return if @options.width? then @options.width else "#{@form_field.offsetWidth}px"

  # class methods and variables ============================================================ 

  @browser_is_supported: ->
    if window.navigator.appName == "Microsoft Internet Explorer"
      return null isnt document.documentMode >= 8
    return true

  @default_multiple_text: "Select Some Options"
  @default_single_text: "Select an Option"
  @default_no_result_text: "No results match"

root.AbstractChosen = AbstractChosen
