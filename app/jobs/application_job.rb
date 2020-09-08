class ApplicationJob < ActiveJob::Base
  include CommonSweepers

  # the name of the queue the job will be places on - so that multiple workers can watch different queues.
  queue_as QueueNames::DEFAULT
  queue_with_priority  2

  # time limit for the whole job to run, after which a timeout exception will be raised
  def timelimit
    15.minutes
  end

  # time before the job is run
  def default_delay
    3.seconds
  end

  # whether a new job will be created once this one finishes.
  # for example, sending weekly emails once finished creates a new job to start in 1 week
  def follow_on_job?
    false
  end

  def default_priority
    self.class.default_priority
  end

  # the delay for the follow on job, which defaults to the default delay but could be different
  def follow_on_delay
    1.second
  end

  around_perform do |job, block|
    Timeout.timeout(job.timelimit) do
      block.call
    end
  end

  after_perform do |job|
    if job.follow_on_job?
      job.queue_job(nil, follow_on_delay.from_now)
    end
  end

  rescue_from(Exception) do |exception|
    raise exception if Rails.env.test?
    report_exception(exception)
  end

  # adds the job to the Delayed Job queue. Will not create it if it already exists and allow_duplicate is false,
  # or by default allow_duplicate_jobs? returns false.
  def queue_job(priority = nil, time = default_delay.from_now)
    args = { wait_until: time }
    args[:priority] = priority if priority

    enqueue(args)
  end

  def self.report_exception(exception, message = nil, data = {})
    message ||= "Error executing job for #{self.class.name}"
    Seek::Errors::ExceptionForwarder.send_notification(exception, data: data)
    Rails.logger.error(message)
    Rails.logger.error(exception)
  end
end