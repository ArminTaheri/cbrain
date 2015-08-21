
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Complement of the ViewScopes controller module containing view helpers to
# create, update and display Scope elements.
#
# See the ViewScopes module (lib/scope_helpers.rb) for more information on
# view scopes.
module ScopeHelper

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  # Generate URL parameters suitable for +url_for+ to update the session scope
  # named +name+ to match +scope+ (a Scope instance or a hash representation)
  # via +update_session_scopes+. For example, to change the first filter of the
  # 'userfiles' scope:
  #   @scope = scope_from_session('userfiles')
  #   # ...
  #   new_scope = @scope.dup
  #   new_scope.filters[0].operator = '!='
  #   query_params = scope_params('userfiles', new_scope)
  # Same as above, using the hash representation of +@scope+:
  #   @scope = scope_from_session('userfiles')
  #   # ...
  #   scope_hash = @scope.to_hash
  #   scope_hash['filters'][0]['operator'] = '!='
  #   scope_hash = @scope.class.compact_hash(scope_hash)
  #   query_params = scope_params('userfiles', scope_hash)
  # Unless +compress+ is specified as false, the generated URL parameters will
  # use the compressed format as specified by +compress_scope+.
  def scope_params(name, scope, compress: true)
    scope = scope.to_hash if scope.is_a?(Scope)
    scope = Scope.compact_hash(scope)
    scope = ViewScopes.compress_scope(scope) if compress

    { '_scopes' => { name => scope } }
  end

  # Generate URL parameters suitable for +url_for+ to update the session scope
  # named +scope+'s filters (via +update_session_scopes+) via a given
  # +operation+. +filters+ is expected to be Filter instances or hash
  # representations (a single filter or an Enumerable), depending on which
  # +operation+ is to be performed, and +operation+ is expected to be one of:
  # [+:add+]
  #  Add one or more +filters+ to the specified scope.
  # [+:remove+]
  #  Remove one or more +filters+ from the specified scope.
  # [+:set+]
  #  Add one or more +filters+ to the specified scope, replacing existing
  #  filters filtering on the same attributes as +filters+.
  # [+:replace+]
  #  Replace all filters in the specified scope by the ones in +filters+.
  # [+:clear+]
  #  Remove all filters in the specified scope (+filters is ignored).
  #  Equivalent to using +:replace+ with an empty +filters+.
  #
  # +scope+ defaults to the current route's scope name (see
  # +default_scope_name+).
  #
  # Note that the generated URL parameters are in compressed format (see
  # +compress_scope+).
  def scope_filter_params(operation, filters, scope: nil)
    scope ||= default_scope_name
    filters = (filters.is_a?(Array) ? filters : [filters]).map do |filter|
      filter = filter.to_hash if filter.is_a?(Scope::Filter)
      Scope::Filter.compact_hash(filter)
    end

    ScopeHelper.scope_items_url_params(scope, operation, :filters, filters)
  end

  # Generate URL parameters suitable for +url_for+ to update the session scope
  # named +scope+'s ordering rules (via +update_session_scopes+) via a given
  # +operation+. This method behaves just like +scope_filter_params+, but
  # operates on a Scope's ordering rules (Order instances or hash representations)
  # instead of filters. As such, the same +operation+s are available (:add,
  # :remove, :set, :replace, :clear) and the +scope+ and +orders+ parameters are
  # handled the exact same way +scope_filter_params+'s +scope+ and +filters+
  # parameters are handled.
  def scope_order_params(operation, orders, scope: nil)
    scope ||= default_scope_name
    orders = (orders.is_a?(Array) ? orders : [orders]).map do |order|
      order = order.to_hash if order.is_a?(Scope::Order)
      Scope::Order.compact_hash(order)
    end

    ScopeHelper.scope_items_url_params(scope, operation, :order, orders)
  end

  # Generate URL parameters suitable for +url_for+ to update the session
  # scope named +scope+'s custom attributes with +custom+ (expected to be
  # a hash of attributes to merge in) using CbrainSession's +update+ method.
  #
  # +scope+ defaults to the current route's scope name (see
  # +default_scope_name+).
  #
  # Note that as with +scope_filter_params+ and +scope_order_params+, the
  # generated URL parameters are compressed using +compress_scope+.
  def scope_custom_params(custom, scope: nil)
    scope ||= default_scope_name

    { '_scopes' => { scope => ViewScopes.compress_scope({
      'c' => custom
    }) } }
  end

  # Generate a pretty string representation of +filter+, optionally using
  # +model+ (as the model +filter+ is applied to) to resolve associations
  # to names (instead of IDs). For example, a filter for +:user_id == 1+
  # could have a string representation of 'User: admin' while one for
  # +:status in ['A', 'B', 'C']+ could have 'Status: one of A, B or C'.
  #
  # TODO Ruby collections
  #
  # Note that this method is rather inflexible on how the representations
  # are generated and relies on internal mappings for certain known
  # attributes, values and associations.
  def pretty_scope_filter(filter, model: nil)
    # UI names for certain associations.
    association_names = {
      'group'    => 'project',
      'bourreau' => 'server'
    }

    # Explanatory flag (boolean attributes) value names to use instead of
    # '<attribute>: true' or '<attribute>: false'.
    flag_names = {
      'critical' => ['Critical', 'Not critical'],
      'read'     => ['Read',     'Unread'],
      'locked'   => ['Locked',   'Unlocked']
    }

    # Model methods/attributes to use as representation of a model record
    naming_methods = {
      :user => :login
    }

    attribute = filter.attribute.to_s
    operator  = filter.operator.to_s
    values    = Array(filter.value)

    # Known flags are expected to never be association attributes, and the
    # possible values are fully represented in flag_names. If +filter+'s
    # attribute is in flag_names, the corresponding flag value name is
    # the filter's representation.
    if flag = flag_names[attribute]
      return values.first ? flag.first : flag.last
    end

    # Is +filter+'s attribute an association attribute? If so, resolve it
    # and use it to fetch nicer representations for +filter+'s attribute
    # and values.
    if model
      model = model.to_s.classify.constantize unless
        (model <= ActiveRecord::Base rescue nil)
      association = model.reflect_on_all_associations(:belongs_to)
        .find { |a| a.foreign_key == attribute }

      if association
        attribute = association.name.to_s
        attribute = association_names[attribute] if
          association_names[attribute]

        name_method = (
          naming_methods[association.foreign_key.to_sym] ||
          naming_methods[association.name.to_sym] ||
          :name
        )
        values.map! do |value|
          record = association.klass.find_by_id(value)
          record ? record.send(name_method) : value
        end
      end
    end

    # The type attribute has a special meaning; it usually corresponds to the
    # ActiveRecord class name.
    values.map! { |value| value.constantize.pretty_type rescue value } if
      attribute == 'type'

    # Convert the values to a textual representation, depending on which
    # operator they will be used with; single values are as-is, but
    # sets are converted to 'A, B or C' and ranges to 'A and B'.
    values = (
      if ['in', 'out'].include?(operator)
        values.map! { |v| v.to_s =~ /[,\s]/ ? "'#{v}'" : v.to_s }
        last = values.pop
        values.empty? ? last : "#{values.join(', ')} or #{last}"
      elsif operator == 'range'
        min, max = values.sort
        "#{min} and #{max}"
      else
        values.first.to_s
      end
    )

    # Have a nice textual representation of the operator
    operator = ({
      '=='    => '',
      '!='    => 'not ',
      '>'     => 'over ',
      '>='    => 'over ',
      '<'     => 'under ',
      '<='    => 'under ',
      'in'    => 'one of ',
      'out'   => 'anything except ',
      'match' => '~',
      'range' => 'between '
    })[filter.operator.to_s]

    "#{attribute.humanize}: #{operator}#{values}"
  end

  # Fetch the possible values (and their count) for +attribute+ within
  # +collection+, which is either a Ruby Enumerable or ActiveRecord model.
  # As this method is intended as a view helper to create the list of values to
  # filter a collection/model with, the possible values are returned as a list
  # of hashes matching +DynamicTable+'s filter format, containing:
  # [:value]
  #  Possible value for +attribute+.
  # [:label]
  #  String representation of +:value+ (or just +:value+ if unavailable).
  # [:indicator]
  #  Count of how many times this specific +:value: was found for +attribute+ in
  #  +collection+.
  #
  # If +label+ is specified, it is expected to be an attribute name as a string
  # or symbol (like +attribute+), representing which +collection+ attribute to
  # use as value labels.
  #
  # If +association+ is specified, it is expected to be in the same format as
  # +Scope+::+Filter+'s *association* attribute, and fulfills roughly the same
  # purpose; allow +attribute+ and +label+ to refer to attributes on the joined
  # model (only applicable if +collection+ is an ActiveRecord model).
  def filter_values_for(collection, attribute, label: nil, association: nil)
    # TODO Unscoped/base scope/total item count.

    if (collection <= ActiveRecord::Base rescue nil)
      # Resolve and validate the main +attribute+ to fetch the values of
      attribute, model = ViewScopes.resolve_model_attribute(attribute, collection, association)

      # And +label+, if provided
      if label
        label, model = ViewScopes.resolve_model_attribute(label, model, association)
      else
        label = attribute
      end

      # NOTE: The 'AS' specifier bypasses Rails' uniq on the column names, which
      # would remove the label column if label happens to have the same value
      # as attribute.
      label_alias = model.connection.quote_column_name('label')

      model
        .where("#{attribute} IS NOT NULL")
        .order(attribute, label)
        .group(attribute, label)
        .raw_rows(attribute, "#{label} AS #{label_alias}", "COUNT(#{attribute})")
        .reject { |r| r.first.blank? }
        .map    { |v, l, c| { :value => v, :label => l, :indicator => c } }

    else
      # Make sure +attribute+ and +label+ can be accessed in
      # +collection+'s items.
      attr_get = ViewScopes.generate_getter(collection.first, attribute)
      raise "no way to get '#{attribute}' out of collection items" unless attr_get

      if label == attribute
        lbl_get = attr_get
      else
        lbl_get = ViewScopes.generate_getter(collection.first, label || attribute)
        raise "no way to get '#{label}' out of collection items" unless lbl_get
      end

      collection
        .map     { |i| [attr_get.(i), lbl_get.(i)].freeze }
        .reject  { |v, l| v.blank? }
        .sort_by { |v, l| v }
        .inject(Hash.new(0)) { |h, i| h[i] += 1; h }
        .map { |(v, l), c| { :value => v, :label => l, :indicator => c } }
    end
  end

  # Utility/internal methods

  # Generate URL parameters suitable for +url_for+ to update the session scope
  # named +scope+'s items (ordering or filtering rules). This method is the
  # internal implementation of +scope_filter_params+ (and +scope_order_params+).
  # - +operation+ corresponds exactly to +scope_filter_params+'s +operation+
  # parameter.
  # - +scope+ corresponds to +scope_filter_params+'s +scope+ parameter, minus
  # the default value.
  # - +attr+ is expected to be either :filters, to update scope filtering rules,
  # or :order, for ordering rules. It corresponds to the Scope attribute name
  # to apply +changes+ on.
  # - +changes+ corresponds to +scope_filter_params+'s +changes+ parameter, and
  # is expected to be an array of compact hash representations of filters
  # (Scope::Filter) or ordering rules (Scope::Order).
  #
  # Note that unlike most other utility methods, this method is exclusively
  # intended to be used only to implement +scope_filter_params+ and
  # +scope_order_params+ and is most likely unsuitable for anything else.
  def self.scope_items_url_params(scope, operation, attr, changes) #:nodoc:
    return if changes.blank? && operation != :clear

    key  = (attr == :filters ? 'f' : 'o')
    hash = (
      case operation
      when :set
        replaced  = changes.map { |c| c['a'] }
        changes  += scope_from_session(scope)
          .send(attr)
          .reject { |c| replaced.include?(f.attribute) }
        { key => changes }
      when :clear
        { key => [] }
      else
        { key => changes }
      end
    )

    mode = (
      case operation
      when :add    then :append
      when :remove then :delete
      else :replace
      end
    )

    {
      '_scope_mode' => mode,
      '_scopes' => {
        scope => ViewScopes.compress_scope(hash)
      }
    }
  end

end
