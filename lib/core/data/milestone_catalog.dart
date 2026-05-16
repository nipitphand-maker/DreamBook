class MilestoneDef {
  const MilestoneDef({
    required this.id,
    required this.labelEn,
    required this.labelTh,
    required this.minMonths,
    required this.maxMonths,
  });

  final String id;
  final String labelEn;
  final String labelTh;
  final int minMonths;
  final int maxMonths;
}

const List<MilestoneDef> kMilestoneCatalog = [
  MilestoneDef(
    id: 'gross_motor_holds_head_briefly',
    labelEn: 'Holds head up briefly',
    labelTh: 'ยกหัวขึ้นได้ชั่วคราว',
    minMonths: 1,
    maxMonths: 2,
  ),
  MilestoneDef(
    id: 'social_smile',
    labelEn: 'Social smile',
    labelTh: 'ยิ้มตอบสนอง',
    minMonths: 1,
    maxMonths: 2,
  ),
  MilestoneDef(
    id: 'visual_tracks_objects',
    labelEn: 'Tracks moving objects with eyes',
    labelTh: 'ติดตามสิ่งของที่เคลื่อนไหวด้วยสายตา',
    minMonths: 1,
    maxMonths: 2,
  ),
  MilestoneDef(
    id: 'gross_motor_holds_head_steady',
    labelEn: 'Holds head steady without support',
    labelTh: 'ยกหัวได้มั่นคงโดยไม่ต้องประคอง',
    minMonths: 3,
    maxMonths: 4,
  ),
  MilestoneDef(
    id: 'social_laughs',
    labelEn: 'Laughs out loud',
    labelTh: 'หัวเราะออกเสียง',
    minMonths: 3,
    maxMonths: 4,
  ),
  MilestoneDef(
    id: 'fine_motor_reaches_objects',
    labelEn: 'Reaches for objects',
    labelTh: 'เอื้อมมือหยิบของ',
    minMonths: 3,
    maxMonths: 4,
  ),
  MilestoneDef(
    id: 'gross_motor_rolls_tummy_to_back',
    labelEn: 'Rolls over (tummy to back)',
    labelTh: 'พลิกตัวจากนอนคว่ำเป็นนอนหงาย',
    minMonths: 5,
    maxMonths: 6,
  ),
  MilestoneDef(
    id: 'gross_motor_sits_with_support',
    labelEn: 'Sits with support',
    labelTh: 'นั่งได้โดยมีคนประคอง',
    minMonths: 5,
    maxMonths: 6,
  ),
  MilestoneDef(
    id: 'fine_motor_passes_objects_hand_to_hand',
    labelEn: 'Passes objects from hand to hand',
    labelTh: 'ส่งของจากมือหนึ่งไปอีกมือ',
    minMonths: 5,
    maxMonths: 6,
  ),
  MilestoneDef(
    id: 'gross_motor_sits_without_support',
    labelEn: 'Sits without support',
    labelTh: 'นั่งได้เองโดยไม่ต้องประคอง',
    minMonths: 7,
    maxMonths: 9,
  ),
  MilestoneDef(
    id: 'gross_motor_crawls',
    labelEn: 'Crawls',
    labelTh: 'คลาน',
    minMonths: 7,
    maxMonths: 9,
  ),
  MilestoneDef(
    id: 'language_first_babbling',
    labelEn: 'First babbling (da-da, ma-ma)',
    labelTh: 'เริ่มพูดเสียงอ้อแอ้ (ดา-ดา, มา-มา)',
    minMonths: 7,
    maxMonths: 9,
  ),
  MilestoneDef(
    id: 'social_waves_bye',
    labelEn: 'Waves bye-bye',
    labelTh: 'โบกมือบ๊ายบาย',
    minMonths: 7,
    maxMonths: 9,
  ),
  MilestoneDef(
    id: 'gross_motor_pulls_to_stand',
    labelEn: 'Pulls to stand',
    labelTh: 'ดึงตัวเองยืนขึ้น',
    minMonths: 10,
    maxMonths: 12,
  ),
  MilestoneDef(
    id: 'gross_motor_first_steps',
    labelEn: 'First steps',
    labelTh: 'ก้าวเดินครั้งแรก',
    minMonths: 10,
    maxMonths: 12,
  ),
  MilestoneDef(
    id: 'language_first_words',
    labelEn: 'First meaningful words',
    labelTh: 'พูดคำแรกที่มีความหมาย',
    minMonths: 10,
    maxMonths: 12,
  ),
  MilestoneDef(
    id: 'fine_motor_pincer_grasp',
    labelEn: 'Pincer grasp (uses thumb and finger)',
    labelTh: 'หยิบของด้วยนิ้วโป้งและนิ้วชี้',
    minMonths: 10,
    maxMonths: 12,
  ),
  MilestoneDef(
    id: 'gross_motor_walks_independently',
    labelEn: 'Walks independently',
    labelTh: 'เดินได้เองโดยไม่ต้องจูง',
    minMonths: 13,
    maxMonths: 18,
  ),
  MilestoneDef(
    id: 'language_five_words',
    labelEn: 'Says 5 or more words',
    labelTh: 'พูดได้ 5 คำขึ้นไป',
    minMonths: 13,
    maxMonths: 18,
  ),
  MilestoneDef(
    id: 'social_points_to_things',
    labelEn: 'Points to things of interest',
    labelTh: 'ชี้ไปที่สิ่งที่สนใจ',
    minMonths: 13,
    maxMonths: 18,
  ),
  MilestoneDef(
    id: 'self_care_drinks_from_cup',
    labelEn: 'Drinks from a cup',
    labelTh: 'ดื่มน้ำจากแก้วได้',
    minMonths: 13,
    maxMonths: 18,
  ),
  MilestoneDef(
    id: 'gross_motor_runs',
    labelEn: 'Runs',
    labelTh: 'วิ่งได้',
    minMonths: 19,
    maxMonths: 24,
  ),
  MilestoneDef(
    id: 'language_two_word_phrases',
    labelEn: 'Uses two-word phrases',
    labelTh: 'พูดประโยคสองคำ',
    minMonths: 19,
    maxMonths: 24,
  ),
  MilestoneDef(
    id: 'language_names_body_parts',
    labelEn: 'Names body parts',
    labelTh: 'บอกชื่ออวัยวะร่างกายได้',
    minMonths: 19,
    maxMonths: 24,
  ),
  MilestoneDef(
    id: 'gross_motor_kicks_ball',
    labelEn: 'Kicks a ball',
    labelTh: 'เตะลูกบอลได้',
    minMonths: 19,
    maxMonths: 24,
  ),
];
