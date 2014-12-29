
{ prefs } = require 'prefs'
{ manager } = require 'ruleset/manager'
{ DomainDomainTypeRS } = require 'ruleset/code-ruleset'
{ tabs } = require 'tabs'
{
  removeChildren
  mutateAttribute
} = require 'utils'

{ l10n } = require 'l10n'

idnService = Cc["@mozilla.org/network/idn-service;1"]
              .getService Ci.nsIIDNService


{
  CHROME_DOMAIN
  USER_AVAILABLE_CONTENT_TYPES
} = DomainDomainTypeRS::


temporaryRuleMenu =
  init: ->
    @$ = $ '#temporary-rule-menu'
    $('#temporary-rule-menu > .menu-remove').addEventListener 'command', ->
      selectedRows = temporaryRules.getSelectedRows()
      for i in selectedRows
        [o, d, t] = temporaryRules.getRule i
        manager.get('user_temporary').revoke o, d, t
      temporaryRules.update()
    $('#temporary-rule-menu > .menu-promote').addEventListener 'command', ->
      selectedRows = temporaryRules.getSelectedRows()
      for i in selectedRows
        [o, d, t, decision] = temporaryRules.getRule i
        manager.get('user_temporary').revoke(o, d, t)
        manager.get('user_persistent')[if decision then 'allow' else 'reject'](o, d, t)
      temporaryRules.update()
      persistentRules.update()

  open: (x, y) ->
    @$.openPopupAtScreen x, y, true


persistentRuleMenu =
  init: ->
    @$ = $ '#persistent-rule-menu'
    $('#persistent-rule-menu > .menu-remove').addEventListener 'command', ->
      selectedRows = persistentRules.getSelectedRows()
      for i in selectedRows
        [o, d, t] = persistentRules.getRule i
        manager.get('user_persistent').revoke o, d, t
      persistentRules.update()
  open: (x, y) ->
    @$.openPopupAtScreen x, y, true


class AddRuleWidget
  constructor: (@_containerSelector, @_rulesetId) ->

  init: ->
    container = $ @_containerSelector

    container.appendChild box = createElement 'hbox',
      align: 'center'
      flex: 1

    box.appendChild @_decisionList = createElement 'menulist',
      _children_:
        menupopup: {}

    for decision in ['allow', 'reject']
      @_decisionList.menupopup.appendChild createElement 'menuitem',
        label: l10n "preferences_custom_rule.#{decision}"
        value: decision
    @_decisionList.selectedIndex = 0

    box.appendChild @_typeList = createElement 'menulist',
      _children_:
        menupopup: {}

    for type in USER_AVAILABLE_CONTENT_TYPES
      @_typeList.menupopup.appendChild createElement 'menuitem',
        label: l10n "content_type.title.plural.#{type}"
        value: type
    @_typeList.selectedIndex = 0

    box.appendChild @_originTextbox = createElement 'textbox',
      placeholder: l10n "origin_domain"
      class: "compact"
      flex: 1

    box.appendChild @_destinationTextbox = createElement 'textbox',
      placeholder: l10n "destination_domain"
      class: "compact"
      flex: 1

    box.appendChild @_addButton = createElement 'button',
      label: l10n "preferences_custom_rule.add"
      icon: "add"

    @_addButton.addEventListener 'command', @_addButtonClick.bind this

    addOnEnterPress = (event) ->
      if event.keyCode == 13 # Enter
        do add
    @_originTextbox.addEventListener 'keypress', addOnEnterPress
    @_destinationTextbox.addEventListener 'keypress', addOnEnterPress

  WEB_HOST_RE = ///
    ^(
      ([^\.]+\.)+[^\.]+ # something like an IDN or ip4 address
    )?$
  ///i

  _validateHost: (textbox) ->
    str = textbox.value.toLowerCase()
    if idnService.isACE str
      # Doc on `nsIIDNService` says `convertToDisplayIDN` ensures that
      # the encoding is consistent with `nsIURI.host` which is precisely
      # what we want here
      str = idnService.convertToDisplayIDN str, no
    return str if WEB_HOST_RE.test str
    textbox.select()
    textbox.focus()
    return null

  _addButtonClick: ->
    allowReject = @_decisionList.selectedItem.value
    type = @_typeList.selectedItem.value
    origin = @_validateHost @_originTextbox
    destination = @_validateHost @_destinationTextbox
    return if origin is null or destination is null
    manager.get(@_rulesetId)[allowReject](origin, destination, type)


addTemporaryRuleWidget = new (class extends AddRuleWidget
  _addButtonClick: ->
    super arguments...
    temporaryRules.update()
) '#add-temporary-rule-container', 'user_temporary'

addPersistentRuleWidget = new (class extends AddRuleWidget
  _addButtonClick: ->
    super arguments...
    persistentRules.update()
) '#add-persistent-rule-container', 'user_persistent'


class RulesTree
  COLUMNS_COUNT = 4

  constructor: (@_selector, @_searchSelector, @_rulesetId) ->

  init: ->
    @_searchBox = $ @_searchSelector

    container = $ @_selector
    container.appendChild @$ = createElement 'tree',
      flex: 1
      enableColumnDrag: "true"
      persist: "sortDirection sortResource"
      sortDirection: "ascending"
      sortResource: "description"

    @$.appendChild treecols = createElement 'treecols'
    @$.appendChild createElement 'treechildren'

    appendTreecol = (description) ->
      {
        label
        sortResource
      } = description
      treecols.appendChild createElement 'treecol',
        label: l10n label
        sortResource: sortResource
        persist: 'width ordinal hidden'
        flex: 1

    appendTreecol
      label: 'decision'
      sortResource: 'decision'
    appendTreecol
      label: 'content_type'
      sortResource: 'type'
    appendTreecol
      label: 'origin_domain'
      sortResource: 'origin'
    appendTreecol
      label: 'destination_domain'
      sortResource: 'destination'

    that = this
    @$.addEventListener 'contextmenu', (event) ->
      return unless event.target.nodeName == 'treechildren' \
                    and that._treeView.selection.count > 0
      that._onTreechildrenContextMenu event

    @$.addEventListener 'keypress', (event) ->
      if event.keyCode == 46 # Delete
        selectedRows = that.getSelectedRows()
        for i in selectedRows
          [o, d, t] = that.getRule i
          manager.get(that._rulesetId).revoke o, d, t
        that.update()

    for col in @$.getElementsByTagName 'treecol'
      col.addEventListener 'click', ->
        for col in that.$.getElementsByTagName 'treecol'
          if col isnt this
            col.removeAttribute 'sortDirection'
        mutateAttribute this, 'sortDirection', (order) ->
          if order == 'ascending' then 'descending' else 'ascending'
        that.$.setAttribute 'sortResource', this.getAttribute 'sortResource'
        that.$.setAttribute 'sortDirection', this.getAttribute 'sortDirection'
        that.update()

    @_searchBox.addEventListener 'command', ->
      that._filter = this.value
      that.update()
    @update()

  getSelectedRows: ->
    selection = @_treeView.selection
    selectedRows = []

    if selection.single
      selectedRows.push selection.currentIndex
      return selectedRows

    start = {}
    end = {}
    for i in [0...selection.getRangeCount()]
      selection.getRangeAt i, start, end
      for j in [start.value..end.value]
        selectedRows.push j
    return selectedRows

  getRule: (i) -> @_rows[i].source

  _onTreechildrenContextMenu: ->

  localizeTypeLookup = {}
  for t in DomainDomainTypeRS::USER_AVAILABLE_CONTENT_TYPES
    localizeTypeLookup[t] = l10n 'content_type.title.plural.' + t

  localizeDomainLookup = {}
  localizeDomainLookup[CHROME_DOMAIN] = l10n 'preferences_chrome_domain'
  localizeDomainLookup[''] = l10n 'preferences_any_domain'

  localizeDecisionLookup = {
    true: l10n 'allow'
    false: l10n 'reject'
  }

  update: ->
    @_rows = []
    for rule in manager.get(@_rulesetId).toTable()
      [o, d, t, dec] = rule
      origin = if o of localizeDomainLookup \
               then localizeDomainLookup[o] \
               else o
      destination = if d of localizeDomainLookup \
                    then localizeDomainLookup[d] \
                    else d
      type = localizeTypeLookup[t]
      decision = localizeDecisionLookup[dec]
      @_rows.push {
        decision,    0: decision
        type,        1: type
        origin,      2: origin
        destination, 3: destination
        length: 4
        source: rule
      }

    if @_filter
      filter = @_filter.toLowerCase()
      @_rows = @_rows.filter ({origin, destination, type, decision}) ->
        return origin.toLowerCase().contains(filter) \
               or destination.toLowerCase().contains(filter) \
               or type.toLowerCase().contains(filter) \
               or decision.toLowerCase().contains(filter)

    sortResource = @$.getAttribute 'sortResource'
    sortDirection = if 'ascending' == @$.getAttribute 'sortDirection' \
      then 1 \
      else -1
    @_rows.sort (rowA, rowB) ->
      a = rowA[sortResource]
      b = rowB[sortResource]
      if a < b
        return - sortDirection
      if a > b
        return sortDirection
      return 0

    that = this
    @_treeView =
      rowCount: that._rows.length
      getCellText: (row, column) -> that._rows[row][column.index]
      setTree: (@treebox) ->
      cycleHeader: (col, elem) ->
      isContainer: (row) -> no
    @$.view = @_treeView

persistentRules = new (class extends RulesTree
  _onTreechildrenContextMenu: (e) ->
    persistentRuleMenu.open e.screenX, e.screenY
) '#persistent-rules', '#persistent-rules-search-box', 'user_persistent'

temporaryRules = new (class extends RulesTree
  _onTreechildrenContextMenu: (e) ->
    temporaryRuleMenu.open e.screenX, e.screenY
) '#temporary-rules', '#temporary-rules-search-box', 'user_temporary'


onLoad = ->
  temporaryRules.init()
  persistentRules.init()
  temporaryRuleMenu.init()
  persistentRuleMenu.init()
  addTemporaryRuleWidget.init()
  addPersistentRuleWidget.init()