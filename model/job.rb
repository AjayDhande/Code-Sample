class Job < ActiveRecord::Base
  DELIVERY_METHODS = ['Standard', "Express", "Special"]

  include PgSearch
  include TimeFormatting

  validates :client,         presence: true
  validates :description,    presence: true
  validates :printing_press, relation_with_print_supplier_required: true
  validates :substrate,      relation_with_print_supplier_required: true
  validates :cylinder,       relation_with_print_supplier_required: true
  validates :sr_layout,      inclusion: { in: Constant.sr_layouts }, if: :sr_layout?
  validates :printing_mode,  inclusion: { in: Constant.printing_modes }, if: :printing_mode?
  validates :priority,       inclusion: { in: Constant.priorities }, if: :priority?
  validates :stage,          inclusion: { in: Constant.job_stages }
  validate  :label_proper?
  validate do |job|
    if job.plates_arrival_date && job.changes.has_key?(:plates_arrival_date)
      if job.plates_arrival_date <= DateTime.now.to_date
        self.errors[:plates_arrival_date] << "cannot be in the past or today"
      end
    end
  end

  scope :with_labels, -> (labels) { where(label: labels) }
  scope :at_stage, -> (stage) { where(stage: stage) }
  scope :except_stages, -> (stage) { where("stage NOT IN (?)", stage ) }
  scope :unarchived, -> { where("stage != 'archive'")}
  scope :archived, -> { where(stage: "archive") }
  scope :oldest, -> { order("updated_at desc") }
  scope :visible, -> {where(hidden: false)}
  scope :ordered_label, -> { where(label: "Ordered") }
  scope :ordered_inverted_label, -> { where("label != 'Ordered'") }

  belongs_to :print_supplier
  belongs_to :printing_press
  belongs_to :substrate
  belongs_to :cylinder
  belongs_to :client
  belongs_to :team
  belongs_to :end_customer
  belongs_to :owner, class_name: "User"

  has_one :quotation
  has_one :customer_job_ticket

  has_many :colors, -> { order :id }
  has_many :images, as: :attached
  has_many :proof_orders
  has_many :proof_order_details, through: :proof_orders, class_name: "ProofOrder::Detail", source: :details
  has_many :proof_documents, dependent: :destroy
  has_many :notifiers, through: :end_customer
  has_many :links
  has_many :events
  has_many :messages
  has_many :lightboxes, through: :proof_documents
  has_many :team_lightboxes, through: :proof_documents

  delegate :name, :short_name,            to: :client,         prefix: true, allow_nil: true
  delegate :name,                         to: :end_customer,   prefix: true, allow_nil: true
  delegate :name, :short_name,            to: :print_supplier, prefix: true, allow_nil: true
  delegate :name,                         to: :printing_press, prefix: true, allow_nil: true
  delegate :name,                         to: :substrate,      prefix: true, allow_nil: true
  delegate :name, :reduction, :thickness, to: :cylinder,       prefix: true, allow_nil: true

  delegate :backwardable?, to: :state_machine
  delegate :plates_lengths, :plates_widths, :plates_pieces, to: :quotation, allow_nil: true

  accepts_nested_attributes_for :images, :quotation, :proof_orders
  accepts_nested_attributes_for :colors, reject_if: ->(color) { color["name"].blank? && color["action"].blank? && color["length"].blank? && color["notes"].blank? }, allow_destroy: true

  before_validation :set_initial_stage_and_label, on: :create
  after_create :update_system_id
  after_save :write_cached_data

  pg_search_scope :search_by_details,
    against: [:id, :system_id, :description, :first_reference, :second_reference],
    using: {
      tsearch: {
        prefix: true,
        negation: true
      }
    }

  pg_search_scope :dynamic_search, (proc do |query, fields|
    against = []
    associated_against = {}
    fields.each do |field|
      if field.include?(".")
        class_and_field = field.split(".")
        class_name = class_and_field[0]
        field_name = class_and_field[1]
        associated_against[class_name.to_sym] ||= []
        associated_against[class_name.to_sym].push(field_name.to_sym)
      else
        against.push(field)
      end
    end

    {
      against: against,
      associated_against: associated_against,
      using: {
        tsearch: { prefix: true, negation: true }
      },
      query: query
    }
  end)

  def order_plates(params, user)
    message_text = params[:plates_delivery_additional_information]

    self.plates_arrival_date                    = params[:plates_arrival_date]
    self.plates_arrival_delivery_method         = params[:plates_arrival_delivery_method]
    self.plates_delivery_additional_information = params[:plates_delivery_additional_information]
    self.plate_pushed_to_production_at          = DateTime.now

    if self.valid?
      Event::Creator.new(job: self, user: user).ticket_update
      self.save!
    end

    proof_orders_attributes = (params[:proof_orders_attributes] || []).map(&:last)

    proof_orders_attributes.map! { |proof_order|
      proof_order['details_attributes'] = proof_order['details_attributes'].flat_map { |detail|
        detail.last['pieces'].empty? ? nil : detail.last
      }.compact
      proof_order
    }.compact

    proof_orders_attributes.select! { |proof_order| not proof_order['details_attributes'].empty? }

    proof_orders_attributes.each do |proof_params|
      proof_order = self.proof_orders.new(proof_params)
      proof_order.ordering_user = user
      proof_order.save
    end

    if forward_stage_is_plates?
      self.forward!(user)
      message = self.messages.create(text: message_text)
      Event::Creator.new(job: self, user: user).message_creation(message)
    end
  end

  def reorder(reorder_attributes, user)
    self.attributes = reorder_attributes
    if self.valid?
      Event::Creator.new(job: self, user: user).ticket_update
      self.save
    end
    self.stage = "plates"
    self.label = "Reorder"
    self.save
  end

  def custom_job_ticket(customer_ticket_attributes, user)
    self.attributes = customer_ticket_attributes[:job]
    custom_ticket = self.customer_job_ticket
    if self.valid?
      Event::Creator.new(job: self, user: user).ticket_update
      self.save
    end

    #basic information section
    if custom_ticket.basic_information.present?
      basic = custom_ticket.basic_information
      basic.attributes = customer_ticket_attributes[:basic_information]
    else
      basic = custom_ticket.build_basic_information(customer_ticket_attributes[:basic_information])
    end
    if basic.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      basic.save
    end

    #sap information section
    if custom_ticket.sap_information.present?
      sap = custom_ticket.sap_information
      sap.attributes = customer_ticket_attributes[:sap_information]
    else
      sap = custom_ticket.build_sap_information(customer_ticket_attributes[:sap_information])
    end
    if sap.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      sap.save
    end

    #Planning information section
    if custom_ticket.planning_information.present?
      planning = custom_ticket.planning_information
      planning.attributes = customer_ticket_attributes[:planning_information]
    else
      planning = custom_ticket.build_planning_information(customer_ticket_attributes[:planning_information])
    end
    if planning.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      planning.save
    end

    #cost information section
    if custom_ticket.cost_information.present?
      cost = custom_ticket.cost_information
      cost.attributes = customer_ticket_attributes[:cost_information]
    else
      cost = custom_ticket.build_cost_information(customer_ticket_attributes[:cost_information])
    end
    if cost.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      cost.save
    end

    #film specification section
    if custom_ticket.film_specification.present?
      film = custom_ticket.film_specification
      film.attributes = customer_ticket_attributes[:film_specification]
    else
      film = custom_ticket.build_film_specification(customer_ticket_attributes[:film_specification])
    end
    if film.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      film.save
    end

    #bag specification section
    if custom_ticket.bag_specification.present?
      bag = custom_ticket.bag_specification
      bag.attributes = customer_ticket_attributes[:bag_specification]
    else
      bag = custom_ticket.build_bag_specification(customer_ticket_attributes[:bag_specification])
    end
    if bag.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      bag.save
    end

    #carton specification section
    if custom_ticket.carton_specification.present?
      carton = custom_ticket.carton_specification
      carton.attributes = customer_ticket_attributes[:carton_specification]
    else
      carton = custom_ticket.build_carton_specification(customer_ticket_attributes[:carton_specification])
    end
    if carton.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      carton.save
    end

    #tray_and_leading specification section
    if custom_ticket.tray_and_leading_specification.present?
      tray_and_leading = custom_ticket.tray_and_leading_specification
      tray_and_leading.attributes = customer_ticket_attributes[:tray_and_leading_specification]
    else
      tray_and_leading = custom_ticket.build_tray_and_leading_specification(customer_ticket_attributes[:tray_and_leading_specification])
    end
    if tray_and_leading.valid?
      Event::Creator.new(job: self, user: user).custom_ticket_update
      tray_and_leading.save
    end

    custom_ticket.update_attributes(last_edited_by: user.id)
  end

  def recent_plates_arrival_date
    if plates_arrival_date and plates_arrival_delivery_method
      "#{plates_arrival_date.strftime("%y%m%d")} #{plates_arrival_delivery_method}"
    end
  end

  def reorderable?
    ["delivery", "archive"].include?(stage)
  end

  def prefilled_colors
    array_of_colors = self.colors.to_a
    new_colors_amount = 10 - array_of_colors.size
    new_colors_amount.times do
      array_of_colors << Color.new
    end
    array_of_colors
  end

  def duplicate(user)
    Job::Duplicator.new(self, user).duplicate
  end

  def update_state(state_params: params, updating_user: updating_user, message: nil, send_emails: true, create_event: true, send_links: true)
    assign_attributes(state_params)

    if self.valid?
      if self.changes.has_key?('stage')
        self.notification_manager.cleanup_persisted!
        self.notification_manager.cleanup_volatile!
        self.update_attribute(:priority, '')
      elsif self.changes.has_key?('label')
        self.notification_manager.cleanup_volatile!
      end
    end

    touch and save!

    # push proof orders from Quality -> Delivered for certain Job push
    if stage == 'delivery' && label == 'In Process'
      proof_order_details.where(status: 'Quality').update_all(status: 'Delivered')
    end
    @event = Event::Creator.new(job: self, user: updating_user).state_change if create_event
    StateChangedNotificationDispatcher.new(job: self, message: message, send_links: send_links).dispatch if send_emails

    RunTransitionCallbacksService.new(self, event: @event).call(updating_user)
  end

  def create_message_with_event(message_params, updating_user, notify: true)
    message = self.messages.create(message_params)
    Event::Creator.new(job: self, user: updating_user).message_creation(message, notify: notify)
    message
  end

  def printing_press_stations
    (printing_press && printing_press.stations) || 0
  end

  def tasks
    {
      quotation: quotation_task,
      design:    design_task,
      artwork:   artwork_task,
      prepress:  prepress_task,
      plates:    plates_task
    }
  end

  def forwardable?
    !(forward_stage_is_plates? and recent_plates_arrival_date.nil?)
  end

  def forward_stage_is_plates?
    state_machine.forward_stages.first == 'plates'
  end

  def forward_stage
    state_machine.forward_stages.first.humanize
  end

  def client_should_act?
    stage && state_machine.should_act == "Client"
  end

  def should_act
    state_machine.should_act
  end

  def preflight?
    stage == "preflight"
  end

  def quotation?
    stage == "quotation"
  end

  def plates?
    stage == "plates"
  end

  def forward!(updating_user, create_event: true)
    update_state(state_params: state_machine.forward.state, updating_user: updating_user, create_event: create_event)
  end

  def backward!(updating_user)
    update_state(state_params: state_machine.backward.state, updating_user: updating_user) if state_machine.backwardable?
  end

  def quotation_undone!(updating_user)
    params = {stage: "quotation", label: "Approval Needed"}
    update_state(state_params: params, updating_user: updating_user)
  end

  def state
    {
      stage: stage,
      label: label
    }
  end

  def changes_manager
    @changes_manager ||= Job::ChangesManager.new(self)
  end

  def colors_orders
    colors.ordered.pluck(:id, :order).each_with_object({}) {|arr, h| h[arr[0]] = arr[1]}
  end

  def notification_manager
    @notification_manager ||= Job::NotificationManager.new(self)
  end

  def editable_by?(user)
    user.repro? or user.production? or ((user.client? || user.client_manager?) and ["start", "quotation", "prepress", "preflight", "design", "artwork"].include?(stage))
  end
  
  def custom_ticket_editable_by?(user)
    (self.client.customer_job_ticket? and (user.client? || user.client_manager?) and ["start", "quotation", "prepress", "preflight", "design", "artwork"].include?(stage))
  end
  
  def last_message
    @last_message ||= messages.last
  end

  def get_proof_document_by_slot(slot)
    proof_documents_by_slots.dig(slot.to_s, 0)
  end

  def get_archive_proof_documents_by_slot(slot)
    archive_proof_documents_by_slots[slot.to_s]
  end

  def has_proof_document?(slot)
    proof_documents_by_slots[slot.to_s].present?
  end

  def has_archive_proof_documents?(slot)
    archive_proof_documents_by_slots[slot.to_s].present?
  end

  def proof_documents_by_slots
    @proof_documents_by_slots ||= proof_documents.where(archived: false).group_by(&:slot)
  end

  def archive_proof_documents_by_slots
    @archive_proof_documents_by_slots ||= proof_documents.where(archived: true).group_by(&:slot)
  end

  def reorder_colors!
    colors = self.colors.order(order: :asc)
    colors.each_with_index do |color, index|
      new_order = index + 1
      color.update(order: new_order) if color.order != new_order
    end
    write_cached_data
    nil
  end

  private

  def write_cached_data
    ActiveRecord::Base.transaction do
      self.update_column(:cached_plate_names, colors.map(&:plate_short_name).uniq.compact.join(", "))
      self.update_column(:cached_plate_types, colors.map(&:plate_type).uniq.compact.join(", "))
      self.update_column(:proof_order_plates_count_g, proof_order_details.quality_or_in_process.g_type.sum(:pieces))
      self.update_column(:proof_order_plates_count_h, proof_order_details.quality_or_in_process.h_type.sum(:pieces))
      self.update_column(:sleeves_count, colors.map(&:sleeve?).count(true))
      self.update_column(:updated_at_formatted, updated_at_formatted_calculation)
    end
  end

  def state_machine
    @sm ||= StateMachine.new(stage, label, tasks)
  end

  def label_proper?
    if label
      unless state_machine.valid?
        errors.add(:label, "is not allowed")
      end
    end
  end

  def set_initial_stage_and_label
    self.stage = "start" unless stage.present?
    self.label = "Clarify Needed" unless label.present?
  end

  def update_system_id
    update_attribute(:system_id, SystemId.new(self.id).to_s)
  end
end
