user = User.find_or_create_by!(email: "test@example.com")
puts "Test user created:"
puts "  Email: #{user.email}"
puts "  API Token: #{user.api_token}"
