require 'spec_helper'

describe BigbluebuttonMeetingUpdater do

  it "uses the queue :bigbluebutton_rails" do
    BigbluebuttonMeetingUpdater.instance_variable_get(:@queue).should eql(:bigbluebutton_rails)
  end

  describe "#perform" do
    let!(:api) { double(BigBlueButton::BigBlueButtonApi) }

    it "waits the amount of time specified before starting"

    context "calls fetch_meeting_info in the target room" do
      let!(:room) { FactoryGirl.create(:bigbluebutton_room) }

      before {
        expect(BigbluebuttonRoom).to receive(:find).with(room.id).and_return(room)
        expect(room).to receive(:fetch_meeting_info).once
      }
      it { BigbluebuttonMeetingUpdater.perform(room.id) }
    end

    context "calls finish_meetings if an exception 'notFound' is raised" do
      let!(:room) { FactoryGirl.create(:bigbluebutton_room) }
      let!(:exception) {
        e = BigBlueButton::BigBlueButtonException.new('Test error')
        e.key = 'notFound'
        e
      }

      before {
        expect(BigbluebuttonRoom).to receive(:find).with(room.id).and_return(room)
        room.server.stub(:api) { api }
        expect(api).to receive(:get_meeting_info).once { raise exception }
        expect(room).to receive(:finish_meetings).once
      }
      it { expect { BigbluebuttonMeetingUpdater.perform(room.id) }.not_to raise_exception }
    end

    context "calls finish_meetings if an exception other than 'notFound' is raised" do
      let!(:room) { FactoryGirl.create(:bigbluebutton_room) }
      let!(:exception) {
        e = BigBlueButton::BigBlueButtonException.new('Test error')
        e.key = 'anythingElse'
        e
      }

      before {
        expect(BigbluebuttonRoom).to receive(:find).with(room.id).and_return(room)
        room.server.stub(:api) { api }
        expect(api).to receive(:get_meeting_info).once { raise exception }
        expect(room).to receive(:finish_meetings)
      }
      it { expect { BigbluebuttonMeetingUpdater.perform(room.id) }.not_to raise_exception }
    end

    context "calls finish_meetings if an exception with a blank key is raised" do
      let!(:room) { FactoryGirl.create(:bigbluebutton_room) }
      let!(:exception) {
        e = BigBlueButton::BigBlueButtonException.new('Test error')
        e.key = ''
        e
      }

      before {
        expect(BigbluebuttonRoom).to receive(:find).with(room.id).and_return(room)
        room.server.stub(:api) { api }
        expect(api).to receive(:get_meeting_info).once { raise exception }
        expect(room).to receive(:finish_meetings)
      }
      it { expect { BigbluebuttonMeetingUpdater.perform(room.id) }.not_to raise_exception }
    end

    context "doesn't break if the room is not found" do
      let!(:room) { FactoryGirl.create(:bigbluebutton_room) }
      let!(:exception) {
        e = BigBlueButton::BigBlueButtonException.new('Test error')
        e.key = ''
      }

      before {
        expect(BigbluebuttonRoom).to receive(:find).with(room.id).and_return(nil)
        expect(room).not_to receive(:fetch_meeting_info)
        expect(room).not_to receive(:finish_meetings)
      }
      it { BigbluebuttonMeetingUpdater.perform(room.id) }
    end
  end
end
