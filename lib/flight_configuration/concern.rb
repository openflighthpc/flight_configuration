#==============================================================================
# This file has been ported from ActiveSupport:
# https://github.com/rails/rails/blob/83217025a171593547d1268651b446d3533e2019/activesupport/lib/active_support/concern.rb
#==============================================================================
# Copyright (c) 2005-2020 David Heinemeier Hansson
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#==============================================================================

module FlightConfiguration
  module Concern
    class MultipleIncludedBlocks < StandardError #:nodoc:
      def initialize
        super "Cannot define multiple 'included' blocks for a Concern"
      end
    end

    class MultiplePrependBlocks < StandardError #:nodoc:
      def initialize
        super "Cannot define multiple 'prepended' blocks for a Concern"
      end
    end

    def self.extended(base) #:nodoc:
      base.instance_variable_set(:@_dependencies, [])
    end

    def append_features(base) #:nodoc:
      if base.instance_variable_defined?(:@_dependencies)
        base.instance_variable_get(:@_dependencies) << self
        false
      else
        return false if base < self
        @_dependencies.each { |dep| base.include(dep) }
        super
        base.extend const_get(:ClassMethods) if const_defined?(:ClassMethods)
        base.class_eval(&@_included_block) if instance_variable_defined?(:@_included_block)
      end
    end

    def prepend_features(base) #:nodoc:
      if base.instance_variable_defined?(:@_dependencies)
        base.instance_variable_get(:@_dependencies).unshift self
        false
      else
        return false if base < self
        @_dependencies.each { |dep| base.prepend(dep) }
        super
        base.singleton_class.prepend const_get(:ClassMethods) if const_defined?(:ClassMethods)
        base.class_eval(&@_prepended_block) if instance_variable_defined?(:@_prepended_block)
      end
    end

    # Evaluate given block in context of base class,
    # so that you can write class macros here.
    # When you define more than one +included+ block, it raises an exception.
    def included(base = nil, &block)
      if base.nil?
        if instance_variable_defined?(:@_included_block)
          if @_included_block.source_location != block.source_location
            raise MultipleIncludedBlocks
          end
        else
          @_included_block = block
        end
      else
        super
      end
    end

    # Evaluate given block in context of base class,
    # so that you can write class macros here.
    # When you define more than one +prepended+ block, it raises an exception.
    def prepended(base = nil, &block)
      if base.nil?
        if instance_variable_defined?(:@_prepended_block)
          if @_prepended_block.source_location != block.source_location
            raise MultiplePrependBlocks
          end
        else
          @_prepended_block = block
        end
      else
        super
      end
    end

    # Define class methods from given block.
    # You can define private class methods as well.
    #
    #   module Example
    #     extend ActiveSupport::Concern
    #
    #     class_methods do
    #       def foo; puts 'foo'; end
    #
    #       private
    #         def bar; puts 'bar'; end
    #     end
    #   end
    #
    #   class Buzz
    #     include Example
    #   end
    #
    #   Buzz.foo # => "foo"
    #   Buzz.bar # => private method 'bar' called for Buzz:Class(NoMethodError)
    def class_methods(&class_methods_module_definition)
      mod = const_defined?(:ClassMethods, false) ?
        const_get(:ClassMethods) :
        const_set(:ClassMethods, Module.new)

      mod.module_eval(&class_methods_module_definition)
    end
  end
end
