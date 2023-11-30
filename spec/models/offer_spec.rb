shared_examples 'offer time validation' do |offer_start, offer_end|
  context "when #{offer_start} is specified" do
    context "when #{offer_start} is in the past" do
      let(offer_start) { 1.day.ago }

      it { should_not be_valid }

      context 'when the offer is archived' do
        before { subject.aasm_state = :archived }

        it { should be_valid }
      end
    end

    context "when #{offer_start} is not in the past" do
      let(offer_start) { Date.today }

      it { should be_valid }
    end
  end

  context "when #{offer_start} and #{offer_end} are specified" do
    let(offer_start) { 2.days.ago }
    let(offer_end) { 2.days.from_now }

    context "when #{offer_end} is in the past" do
      let(offer_end) { 1.day.ago }

      it { should_not be_valid }

      context 'when the offer is archived' do
        before { subject.aasm_state = :archived }

        it { should be_valid }
      end
    end

    context "when #{offer_start} is after #{offer_end}" do
      let(:start_on) { 2.days.from_now }
      let(:end_on) { 1.day.from_now }

      it { should_not be_valid }
    end

    context "when #{offer_start} is before #{offer_end}" do
      it { should be_valid }
    end
  end
end

describe Offer, type: :model do
  describe 'associations' do
    it { should belong_to(:offerer) }
    it { should have_many(:offer_invitations) }
    it { should have_many(:users).through(:offer_invitations) }
  end

  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:place) }
    it { should validate_presence_of(:time_format) }

    describe 'offer_time_must_be_specified' do
      subject do
        build(:offer,
              :details_specified,
              start_on: start_on,
              end_on: end_on,
              start_at: start_at,
              end_at: end_at)
      end

      let(:start_on) { nil }
      let(:end_on) { nil }
      let(:start_at) { nil }
      let(:end_at) { nil }

      context 'when time is not specified' do
        it 'is not valid' do
          expect(subject.valid?).to eq false
          expect(subject.errors[:base]).to include('time must be specified')
        end
      end

      include_examples 'offer time validation', :start_on, :end_on
    end
  end

  describe 'scopes' do
    describe '.for' do
      subject { described_class.for(user) }

      let(:user) { create(:user) }
      let!(:offer_created_by_user) { create(:offer, offerer: user) }
      let(:offer_with_pending_invitation) { create(:offer) }
      let(:offer_with_accepted_invitation) { create(:offer) }
      let(:offer_with_declined_invitation) { create(:offer) }
      let!(:offer_without_invitation) { create(:offer) }

      before do
        create(:offer_invitation, :pending, offer: offer_with_pending_invitation, user: user)
        create(:offer_invitation, :accepted, offer: offer_with_accepted_invitation, user: user)
        create(:offer_invitation, :declined, offer: offer_with_declined_invitation, user: user)
      end

      it 'returns offers for a given user' do
        expect(subject).to include(
          offer_created_by_user,
          offer_with_pending_invitation,
          offer_with_accepted_invitation
        )
        expect(subject).not_to include(offer_without_invitation)
        expect(subject).not_to include(offer_with_declined_invitation)
      end
    end

    describe '.expired' do
      subject { described_class.expired }

      let(:expired_offer) { build(:offer, :published, start_at: 2.days.ago, end_at: 1.day.ago) }
      let(:archived_offer) { build(:offer, :archived, start_at: 2.days.ago, end_at: 1.day.ago) }
      let(:users_invited_offer) { build(:offer, :users_invited, start_at: 2.days.ago, end_at: 1.day.ago) }
      let!(:active_offer) { build(:offer, start_at: 1.day.from_now, end_at: 2.days.from_now) }

      before do
        expired_offer.save(validate: false)
        expired_offer.save(validate: false)
        users_invited_offer.save(validate: false)
      end

      it 'returns published offers with end_at in the past' do
        expect(subject).to include(expired_offer)
        expect(subject).not_to include(archived_offer, users_invited_offer, active_offer)
      end
    end
  end

  describe 'aasm_state transitions' do
    describe '#invite_users' do
      subject { offer.invite_users }

      let(:offer) { create(:offer, :details_specified) }

      it 'transitions to users_invited' do
        expect { subject }.to change { offer.aasm_state }.from('details_specified').to('users_invited')
      end
    end

    describe '#publish' do
      subject { offer.publish! }

      let(:offer) { create(:offer, :users_invited) }

      before { create_list(:offer_invitation, 3, :draft, offer: offer) }

      it 'transitions to publish' do
        expect { subject }.to change { offer.reload.aasm_state }
                          .from('users_invited').to('published')
      end

      it 'sends invitations' do
        expect { subject }.to change { offer.reload.offer_invitations.pluck(:aasm_state).uniq }
                          .from(%w[draft]).to(%w[pending])
      end
    end

    describe '#archive' do
      subject { offer.archive! }

      let(:offer) { create(:offer, :published) }

      before { create_list(:offer_invitation, 3, :pending, offer: offer) }

      it 'transitions to archived' do
        expect { subject }.to change { offer.reload.aasm_state }
                          .from('published').to('archived')
      end

      it 'expires pending invitations' do
        expect { subject }.to change { offer.reload.offer_invitations.pluck(:aasm_state).uniq }
                          .from(%w[pending]).to(%w[expired])
      end
    end
  end

  describe '#draft?' do
    subject { offer.draft? }

    context 'when offer is in details_specified state' do
      let(:offer) { build(:offer, :details_specified) }

      it { should be_truthy }
    end

    context 'when offer is in users_invited state' do
      let(:offer) { build(:offer, :users_invited) }

      it { should be_truthy }
    end

    context 'when offer is not in details_specified or users_invited state' do
      let(:offer) { build(:offer, :published) }

      it { should be_falsey }
    end
  end

  describe '#publised_or_archived?' do
    subject { offer.published_or_archived? }

    context 'when offer is published' do
      let(:offer) { build(:offer, :published) }

      it { should be_truthy }
    end

    context 'when offer is archived' do
      let(:offer) { build(:offer, :archived) }

      it { should be_truthy }
    end

    context 'when offer is not published nor archived' do
      let(:offer) { build(:offer, :details_specified) }

      it { should be_falsey }
    end
  end

  describe '#expired?' do
    subject { offer.expired? }

    context 'when end_at is in the past for a published offer' do
      let(:offer) { build(:offer, :published, end_at: 1.day.ago) }

      it { should be_truthy }
    end

    context 'when end_at is in the future for a published offer' do
      let(:offer) { build(:offer, :published, end_at: 1.day.from_now) }

      it { should be_falsey }
    end
  end

  describe '#expired_or_archived?' do
    subject { offer.expired_or_archived? }

    context 'when offer is expired' do
      let(:offer) { build(:offer, :published, end_at: 1.day.ago) }

      it { should be_truthy }
    end

    context 'when offer is archived' do
      let(:offer) { build(:offer, :archived) }

      it { should be_truthy }
    end

    context 'when offer is not expired nor archived' do
      let(:offer) { build(:offer, :published, end_at: 1.day.from_now) }

      it { should be_falsey }
    end
  end
end
