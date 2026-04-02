local function greet(name)
  return "Hello " .. name .. "!"
end

local users = { "Devys", "Syntax" }
for _, user in ipairs(users) do
  print(greet(user))
end
