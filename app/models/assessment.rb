class Assessment < ApplicationRecord
  belongs_to :mortgage_application

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  enum :decision, { approved: 0, declined: 1 }

  validates :mortgage_application_id, uniqueness: true
end
