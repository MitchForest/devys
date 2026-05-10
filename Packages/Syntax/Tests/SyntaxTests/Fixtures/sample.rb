# frozen_string_literal: true

class Greeter
  def initialize(name)
    @name = name
  end

  def greet
    "Hello, #{@name}!"
  end
end

greeter = Greeter.new('Devys')
puts greeter.greet

values = [1, 2, 3]
values.each do |value|
  puts value * 2
end
