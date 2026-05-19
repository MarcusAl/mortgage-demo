class User < ApplicationRecord
  has_secure_token :api_token
  has_many :mortgage_applications, dependent: :destroy

  validates :email, presence: true, uniqueness: true
end
