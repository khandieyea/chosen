root = this

class Chosen extends AbstractChosen

  setup: ->
    @current_selectedIndex = @form_field.selectedIndex
    @is_rtl = @form_field.hasClassName "chzn-rtl"

  finish_setup: ->
    @form_field.addClassName "chzn-done"

  set_default_values: ->
    super()

    # HTML Templates
    @single_temp = new Template('<a href="javascript:void(0)" class="chzn-single chzn-default" tabindex="-1"><span>#{default}</span><div><b></b></div></a><div class="chzn-drop"><div class="chzn-search"><input type="text" autocomplete="off" /></div><ul class="chzn-results"></ul></div>')
    @multi_temp = new Template('<ul class="chzn-choices"><li class="search-field"><input type="text" value="#{default}" class="default" autocomplete="off" style="width:25px;" /></li></ul><div class="chzn-drop"><ul class="chzn-results"></ul></div>')
    @no_results_temp = new Template('<li class="no-results">' + @results_none_found + ' "<span>#{terms}</span>"</li>')

  set_up_html: ->
    @container_id = @form_field.identify().replace(/[^\w]/g, '_') + "_chzn"

    container_classes = ["chzn-container"]
    container_classes.push "chzn-container-" + (if @is_multiple then "multi" else "single")
    container_classes.push @form_field.className if @inherit_select_classes && @form_field.className
    container_classes.push "chzn-rtl" if @is_rtl

    container_props =
      'id': @container_id
      'class': container_classes.join ' '
      'style': "width: #{this.container_width()};"
      'title': @form_field.title

    @container = if @is_multiple then new Element('div', container_props).update( @multi_temp.evaluate({ "default": @default_text}) ) else new Element('div', container_props).update( @single_temp.evaluate({ "default":@default_text }) )

    @form_field.hide().insert({ after: @container })
    @dropdown = @container.down('div.chzn-drop')

    @search_field = @container.down('input')
    @search_results = @container.down('ul.chzn-results')
    this.search_field_scale()

    @search_no_results = @container.down('li.no-results')

    if @is_multiple
      @search_choices = @container.down('ul.chzn-choices')
      @search_container = @container.down('li.search-field')
    else
      @search_container = @container.down('div.chzn-search')
      @selected_item = @container.down('.chzn-single')

    this.results_build()
    this.set_tab_index()
    this.set_label_behavior()
    @form_field.fire("liszt:ready", {chosen: this})

  register_observers: ->
    @container.observe "mousedown", (evt) => this.container_mousedown(evt)
    @container.observe "mouseup", (evt) => this.container_mouseup(evt)
    @container.observe "mouseenter", (evt) => this.mouse_enter(evt)
    @container.observe "mouseleave", (evt) => this.mouse_leave(evt)

    @search_results.observe "mouseup", (evt) => this.search_results_mouseup(evt)
    @search_results.observe "mouseover", (evt) => this.search_results_mouseover(evt)
    @search_results.observe "mouseout", (evt) => this.search_results_mouseout(evt)
    @search_results.observe "mousewheel", (evt) => this.search_results_mousewheel(evt)
    @search_results.observe "DOMMouseScroll", (evt) => this.search_results_mousewheel(evt)

    @form_field.observe "liszt:updated", (evt) => this.results_update_field(evt)
    @form_field.observe "liszt:activate", (evt) => this.activate_field(evt)
    @form_field.observe "liszt:open", (evt) => this.container_mousedown(evt)

    @search_field.observe "blur", (evt) => this.input_blur(evt)
    @search_field.observe "keyup", (evt) => this.keyup_checker(evt)
    @search_field.observe "keydown", (evt) => this.keydown_checker(evt)
    @search_field.observe "focus", (evt) => this.input_focus(evt)

    if @is_multiple
      @search_choices.observe "click", (evt) => this.choices_click(evt)
    else
      @container.observe "click", (evt) => evt.preventDefault() # gobble click of anchor

  search_field_disabled: ->
    @is_disabled = @form_field.disabled
    if(@is_disabled)
      @container.addClassName 'chzn-disabled'
      @search_field.disabled = true
      @selected_item.stopObserving "focus", @activate_action if !@is_multiple
      this.close_field()
    else
      @container.removeClassName 'chzn-disabled'
      @search_field.disabled = false
      @selected_item.observe "focus", @activate_action if !@is_multiple

  container_mousedown: (evt) ->
    if !@is_disabled
      if evt and evt.type is "mousedown" and not @results_showing
        evt.stop()

      if not (evt? and evt.target.hasClassName "search-choice-close")
        if not @active_field
          @search_field.clear() if @is_multiple
          document.observe "click", @click_test_action
          this.results_show()
        else if not @is_multiple and evt and (evt.target is @selected_item || evt.target.up("a.chzn-single"))
          this.results_toggle()

        this.activate_field()

  container_mouseup: (evt) ->
    this.results_reset(evt) if evt.target.nodeName is "ABBR" and not @is_disabled

  search_results_mousewheel: (evt) ->
    delta = -evt.wheelDelta or evt.detail
    if delta?
      evt.preventDefault()
      delta = delta * 40 if evt.type is 'DOMMouseScroll'
      @search_results.scrollTop = delta + @search_results.scrollTop

  blur_test: (evt) ->
    this.close_field() if not @active_field and @container.hasClassName("chzn-container-active")

  close_field: ->
    document.stopObserving "click", @click_test_action

    @active_field = false
    this.results_hide()

    @container.removeClassName "chzn-container-active"
    this.clear_backstroke()

    this.show_search_field_default()
    this.search_field_scale()

  activate_field: ->
    @container.addClassName "chzn-container-active"
    @active_field = true

    @search_field.value = @search_field.value
    @search_field.focus()

  test_active_click: (evt) ->
    if evt.target.up('#' + @container_id)
      @active_field = true
    else
      this.close_field()

  results_build: ->
    @parsing = true
    @selected_option_count = null

    @results_data = root.SelectParser.select_to_array @form_field

    if @is_multiple
      @search_choices.select("li.search-choice").invoke("remove")
    else if not @is_multiple
      this.single_set_selected_text()
      if @disable_search or @form_field.options.length <= @disable_search_threshold
        @search_field.readOnly = true
        @container.addClassName "chzn-container-single-nosearch"
      else
        @search_field.readOnly = false
        @container.removeClassName "chzn-container-single-nosearch"

    this.update_results_content this.results_option_build({first:true})

    this.search_field_disabled()
    this.show_search_field_default()
    this.search_field_scale()

    @parsing = false

  result_do_highlight: (el) ->
      this.result_clear_highlight()

      @result_highlight = el
      @result_highlight.addClassName "highlighted"

      maxHeight = parseInt @search_results.getStyle('maxHeight'), 10
      visible_top = @search_results.scrollTop
      visible_bottom = maxHeight + visible_top

      high_top = @result_highlight.positionedOffset().top
      high_bottom = high_top + @result_highlight.getHeight()

      if high_bottom >= visible_bottom
        @search_results.scrollTop = if (high_bottom - maxHeight) > 0 then (high_bottom - maxHeight) else 0
      else if high_top < visible_top
        @search_results.scrollTop = high_top

  result_clear_highlight: ->
    @result_highlight.removeClassName('highlighted') if @result_highlight
    @result_highlight = null

  results_show: ->
    if @is_multiple and @max_selected_options <= this.choices_count()
      @form_field.fire("liszt:maxselected", {chosen: this})
      return false

    @container.addClassName "chzn-with-drop"
    @form_field.fire("liszt:showing_dropdown", {chosen: this})

    @results_showing = true

    @search_field.focus()
    @search_field.value = @search_field.value

    this.winnow_results()

  update_results_content: (content) ->
    @search_results.update content

  results_hide: ->
    if @results_showing
      this.result_clear_highlight()

      @container.removeClassName "chzn-with-drop"
      @form_field.fire("liszt:hiding_dropdown", {chosen: this})

    @results_showing = false


  set_tab_index: (el) ->
    if @form_field.tabIndex
      ti = @form_field.tabIndex
      @form_field.tabIndex = -1
      @search_field.tabIndex = ti

  set_label_behavior: ->
    @form_field_label = @form_field.up("label") # first check for a parent label
    if not @form_field_label?
      @form_field_label = $$("label[for='#{@form_field.id}']").first() #next check for a for=#{id}

    if @form_field_label?
      @form_field_label.observe "click", (evt) => if @is_multiple then this.container_mousedown(evt) else this.activate_field()

  show_search_field_default: ->
    if @is_multiple and this.choices_count() < 1 and not @active_field
      @search_field.value = @default_text
      @search_field.addClassName "default"
    else
      @search_field.value = ""
      @search_field.removeClassName "default"

  search_results_mouseup: (evt) ->
    target = if evt.target.hasClassName("active-result") then evt.target else evt.target.up(".active-result")
    if target
      @result_highlight = target
      this.result_select(evt)
      @search_field.focus()

  search_results_mouseover: (evt) ->
    target = if evt.target.hasClassName("active-result") then evt.target else evt.target.up(".active-result")
    this.result_do_highlight( target ) if target

  search_results_mouseout: (evt) ->
    this.result_clear_highlight() if evt.target.hasClassName('active-result') or evt.target.up('.active-result')

  choice_build: (item) ->
    choice = new Element('li', { class: "search-choice" }).update("<span>#{item.html}</span>")

    if item.disabled
      choice.addClassName 'search-choice-disabled'
    else
      close_link = new Element('a', { href: '#', class: 'search-choice-close', rel: item.array_index })
      close_link.observe "click", (evt) => this.choice_destroy_link_click(evt)
      choice.insert close_link

    @search_container.insert { before: choice }

  choice_destroy_link_click: (evt) ->
    evt.preventDefault()
    evt.stopPropagation()
    this.choice_destroy evt.target unless @is_disabled

  choice_destroy: (link) ->
    if this.result_deselect link.readAttribute("rel")
      this.show_search_field_default()

      this.results_hide() if @is_multiple and this.choices_count() > 0 and @search_field.value.length < 1

      link.up('li').remove()

      this.search_field_scale()

  results_reset: ->
    @form_field.options[0].selected = true
    @selected_option_count = null
    this.single_set_selected_text()
    this.show_search_field_default()
    this.results_reset_cleanup()
    @form_field.simulate("change") if typeof Event.simulate is 'function'
    this.results_hide() if @active_field

  results_reset_cleanup: ->
    @current_selectedIndex = @form_field.selectedIndex
    deselect_trigger = @selected_item.down("abbr")
    deselect_trigger.remove() if(deselect_trigger)

  result_select: (evt) ->
    if @result_highlight
      high = @result_highlight
      this.result_clear_highlight()

      if @is_multiple and @max_selected_options <= this.choices_count()
        @form_field.fire("liszt:maxselected", {chosen: this})
        return false

      if @is_multiple
        high.removeClassName("active-result")
      else
        @search_results.descendants(".result-selected").invoke "removeClassName", "result-selected"
        @result_single_selected = high
      
      high.addClassName("result-selected")

      position = high.id.substr(high.id.lastIndexOf("_") + 1 )
      item = @results_data[position]
      item.selected = true

      @form_field.options[item.options_index].selected = true
      @selected_option_count = null

      if @is_multiple
        this.choice_build item
      else
        this.single_set_selected_text(item.text)

      this.results_hide() unless (evt.metaKey or evt.ctrlKey) and @is_multiple

      @search_field.value = ""

      @form_field.simulate("change") if typeof Event.simulate is 'function' && (@is_multiple || @form_field.selectedIndex != @current_selectedIndex)
      @current_selectedIndex = @form_field.selectedIndex

      this.search_field_scale()

  single_set_selected_text: (text=@default_text) ->
    if text is @default_text
      @selected_item.addClassName("chzn-default")
    else
      this.single_deselect_control_build()
      @selected_item.removeClassName("chzn-default")

    @selected_item.down("span").update(text)

  result_deselect: (pos) ->
    result_data = @results_data[pos]

    if not @form_field.options[result_data.options_index].disabled
      result_data.selected = false

      @form_field.options[result_data.options_index].selected = false
      @selected_option_count = null

      result = $(@container_id + "_o_" + pos)
      result.removeClassName("result-selected").addClassName("active-result").show()

      this.result_clear_highlight()
      this.winnow_results() if @results_showing

      @form_field.simulate("change") if typeof Event.simulate is 'function'
      this.search_field_scale()
      return true
    else
      return false

  single_deselect_control_build: ->
    return unless @allow_single_deselect
    @selected_item.down("span").insert { after: "<abbr class=\"search-choice-close\"></abbr>" } unless @selected_item.down("abbr")
    @selected_item.addClassName("chzn-single-with-deselect")

  get_search_text: ->
    if @search_field.value is @default_text then "" else @search_field.value.strip().escapeHTML()

  winnow_results_set_highlight: ->
    if not @is_multiple
      do_high = @search_results.down(".result-selected.active-result")

    if not do_high?
      do_high = @search_results.down(".active-result")

    this.result_do_highlight do_high if do_high?

  no_results: (terms) ->
    @search_results.insert @no_results_temp.evaluate( terms: terms )

  no_results_clear: ->
    nr = null
    nr.remove() while nr = @search_results.down(".no-results")


  keydown_arrow: ->
    if @results_showing and @result_highlight
      next_sib = @result_highlight.next('.active-result')
      this.result_do_highlight next_sib if next_sib
    else
      this.results_show()

  keyup_arrow: ->
    if not @results_showing and not @is_multiple
      this.results_show()
    else if @result_highlight
      sibs = @result_highlight.previousSiblings()
      actives = @search_results.select("li.active-result")
      prevs = sibs.intersect(actives)

      if prevs.length
        this.result_do_highlight prevs.first()
      else
        this.results_hide() if this.choices_count() > 0
        this.result_clear_highlight()

  keydown_backstroke: ->
    if @pending_backstroke
      this.choice_destroy @pending_backstroke.down("a")
      this.clear_backstroke()
    else
      next_available_destroy = @search_container.siblings().last()
      if next_available_destroy and next_available_destroy.hasClassName("search-choice") and not next_available_destroy.hasClassName("search-choice-disabled")
        @pending_backstroke = next_available_destroy
        @pending_backstroke.addClassName("search-choice-focus") if @pending_backstroke
        if @single_backstroke_delete
          @keydown_backstroke()
        else
          @pending_backstroke.addClassName("search-choice-focus")

  clear_backstroke: ->
    @pending_backstroke.removeClassName("search-choice-focus") if @pending_backstroke
    @pending_backstroke = null

  keydown_checker: (evt) ->
    stroke = evt.which ? evt.keyCode
    this.search_field_scale()

    this.clear_backstroke() if stroke != 8 and this.pending_backstroke

    switch stroke
      when 8
        @backstroke_length = this.search_field.value.length
        break
      when 9
        this.result_select(evt) if this.results_showing and not @is_multiple
        @mouse_on_container = false
        break
      when 13
        evt.preventDefault()
        break
      when 38
        evt.preventDefault()
        this.keyup_arrow()
        break
      when 40
        evt.preventDefault()
        this.keydown_arrow()
        break

  search_field_scale: ->
    if @is_multiple
      h = 0
      w = 0

      style_block = "position:absolute; left: -1000px; top: -1000px; display:none;"
      styles = ['font-size','font-style', 'font-weight', 'font-family','line-height', 'text-transform', 'letter-spacing']

      for style in styles
        style_block += style + ":" + @search_field.getStyle(style) + ";"

      div = new Element('div', { 'style' : style_block }).update(@search_field.value.escapeHTML())
      document.body.appendChild(div)

      w = Element.measure(div, 'width') + 25
      div.remove()

      @f_width = @container.getWidth() unless @f_width

      if( w > @f_width-10 )
        w = @f_width - 10

      @search_field.setStyle({'width': w + 'px'})

root.Chosen = Chosen
