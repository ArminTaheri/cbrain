
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

# ActiveRecord extensions to handle loading and saving STI models.
# Mainly to load and create objects so they are of their actual STI
# +type+, and to get around automatic appending of type to DB queries.
module CBRAINExtensions
  module ActiveRecord
    module SingleTableInheritance
  
      def self.included(includer)
        includer.class_eval do
          extend ClassMethods
        end
      end
  
      # Perform operations in the block provided
      # without adding type information to queries.
      # The receiver is passed to the block provided
      # to allow for the following usage:
      #
      #    minc = MincFile.first
      #    minc.without_type_condition do |m|
      #      m.name = "I am minc"
      #      m.save
      #    end
      def without_type_condition
        self.class.without_type_condition do
          yield(self)
        end
      end
  
      # Subsequent +saves+ or +updates+ WILL NOT
      # include type conditions. 
      def no_type_condition!
        @__no_type_condition__ = true
      end
  
      # Subsequent +saves+ or +updates+ WILL
      # include type conditions.
      def type_condition!
        @__no_type_condition__ = false
      end
      
      # Change class to the variable set in type.
      def class_update(options = {})
        old_class = self.class.to_s
        new_class = self.type.to_s
        return self if old_class == new_class
        
        if self.class.valid_sti_change?(new_class, options)
          new_object = new_class.constantize.new
          instance_variables.each do |var|
            new_object.instance_variable_set(var, instance_variable_get(var))
          end
          new_object.no_type_condition!
        else
          new_object = self
        end
        
        new_object
      end
  
      # Redifine persistance methods to check if 
      # type condition should be applied.
      [:reload, :destroy, :delete].each do |m|
        define_method(m) do |*args|
          if @__no_type_condition__
            without_type_condition do
              super(*args)
            end
          else
            super(*args)
          end
        end
      end
  
      private
      
      def create_or_update #:nodoc:
        if @__no_type_condition__
          without_type_condition do
            super
          end
        else
          super
        end
      end
  
      module ClassMethods
        
        # Find the root of this branch of the STI hierarchy.
        def sti_root_class
          return nil unless self < ::ActiveRecord::Base
          return class_variable_get("@@__sti_root_class__") if class_variable_defined?("@@__sti_root_class__")
  
          if self.superclass == ::ActiveRecord::Base
            root_class = self
          else
            root_class = ancestors.find{ |c| c.is_a?(Class) && c.superclass == ::ActiveRecord::Base }
          end
          root_class.class_variable_set("@@__sti_root_class__", root_class)
  
          root_class  
        end
        
        # Returns true if changing the class of an object from
        # +self+ to +klass+ would be valid.
        #
        # By default, a valid change is to another subclass of
        # of the same sti_root_class. However, if the +root_class+
        # option is defined, the given class will be used as the
        # root of a valid tree.
        def valid_sti_change?(klass, options ={})
          new_class = klass.to_s
          
          if respond_to?(:valid_sti_types)
            valid_types = valid_sti_types
          else          
            superklass = self.sti_root_class 
            root_class = superklass
          
            if options[:root_class] && Class.const_defined?(options[:root_class].to_s)
              option_root_class = options[:root_class].to_s.constantize
              root_class = option_root_class if option_root_class <= superklass
            end
            valid_types = root_class.descendants.map(&:to_s)
  
            if options[:include_root_class]
              valid_types << root_class.to_s
            end
          end
          
          valid_types.include?(new_class) 
        end
  
        # Perform operations in the block provided
        # without adding type information to queries.
        def without_type_condition
          old_finder_needs_type_condition = @finder_needs_type_condition
          @finder_needs_type_condition = :false 
          yield
        ensure
          @finder_needs_type_condition = old_finder_needs_type_condition
        end
        
        # Make it so no_type_condition affects finders.
        def no_type_condition_affects_finders!
          @no_type_condition_affects_finders = true
        end
        
        # Make it so no_type_condition does not affect finders
        # (this is the default).
        def no_type_condition_does_not_affect_finders!
          @no_type_condition_affects_finders = false
        end
        
        # Does no_type_condition affect finders? 
        def no_type_condition_affects_finders?
          if @no_type_condition_affects_finders
            true
          else
            false
          end
        end
        
        # Create a new object with attributes set by +params+.
        # Object will be instantiated with class defined by
        # params[:type], if it's valid.
        #
        # The only option currently accepted is :include_root_class,
        # which considers the sti_root_class to be among the 
        # valid types.
        def sti_new(params = {}, options = {})
          prepare_sti_object(nil, params, options)
        end
        
        # Fetch a record from the database, set its
        # attributes using +params+, and set the class
        # to whatever's in params[:type], if it's 
        # provided.
        #
        # The only option currently accepted is :include_root_class,
        # which considers the sti_root_class to be among the 
        # valid types.
        def sti_load(id, params = {}, options = {})
          prepare_sti_object(id, params, options)
        end
        
        private
        
        # Can be used to intantiate or retrieve an object in the proper class
        # and set its attributes to prepare for saving for saving.
        def prepare_sti_object(id, params = {}, options = {})
          superklass = self.sti_root_class 
          type_update = false
  
          type = params.delete :type 
  
          if type && valid_sti_change?(type, options)
            type_update = true
          end
  
          if type_update #Choose the class of the new object
            klass = type.constantize
          else
            klass = superklass
          end
  
          if id 
            object = superklass.find(id)
            if type_update # Make new model a copy of the old
              object = object.becomes(klass)
              object.type = type
            end
          else
            object = klass.new
          end
  
          if type_update
            object.type = type
          end
  
          object.attributes = params
          object.no_type_condition!
          
          object
        end
        
      end
      
    end
  end
end