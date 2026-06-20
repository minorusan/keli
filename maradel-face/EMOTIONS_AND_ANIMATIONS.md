# Maradel — Emotions & Animations

Reference for the avatar emotion vocabulary (what gemma picks per reply) and the Rocketbox
animation clips available to play (full-body gestures, in-place `_static` set).

---

## Avatar Emotions (22)

From the backend `speech/emotion.ts` `AVATAR_EMOTIONS` — gemma classifies each reply into ONE of
these. A FACE beat drives expression (AK_/AU_ blendshapes); a BODY beat picks a matching gesture.

| id | hint |
|----|------|
| `neutral` | calm, default, matter-of-fact |
| `happy` | pleased, warm, good news |
| `joyful` | delighted, beaming, celebrating |
| `excited` | enthusiastic, energetic, eager |
| `amused` | finds it funny, light chuckle |
| `playful` | teasing, mischievous, joking |
| `affectionate` | warm, caring, fond |
| `proud` | satisfied with an accomplishment, confident |
| `confident` | assured, decisive, in control |
| `curious` | intrigued, wondering, exploring |
| `thoughtful` | reflective, explaining, considering carefully |
| `focused` | concentrated, working, on task |
| `surprised` | astonished, did not expect that |
| `impressed` | admiring, wow, that's good |
| `concerned` | worried, cautious, gentle warning |
| `confused` | puzzled, unsure, doesn't follow |
| `skeptical` | doubtful, unconvinced, raised brow |
| `annoyed` | irritated, mildly frustrated, stern |
| `disappointed` | let down, deflated |
| `sad` | sympathetic, somber, sorry |
| `tired` | weary, low energy, dry |
| `embarrassed` | sheepish, apologetic about a mistake |

---

## Animations (Rocketbox)

- **471** clips total = same animations in 3 root-motion variants: `_static` (in-place, **326**),
  `_xy` (71), `_xyz` (74). **Use `_static`** for a framed avatar (no travel).
- Each exists as `f_<name>` and `m_<name>` (same Bip01 skeleton → plays on any avatar).
- Below: the **182 unique** `_static` animations (gender prefix stripped), grouped.

### cell

- `cell_phone_listen_01` - `cell_phone_talk_01` - `cell_phone_textmessage`


### cheer

- `cheer_01` - `cheer_02` - `cheer_03` - `cheer_04` - `cheer_05`


### claphands

- `claphands_01` - `claphands_02`


### crouch

- `crouch_gestic` - `crouch_idle` - `crouch_in` - `crouch_out`


### dancing

- `dancing_affective` - `dancing_aggressive` - `dancing_cool` - `dancing_neutral` - `dancing_silly`


### documentfile

- `documentfile_idle`


### documents

- `documents_check` - `documents_idle` - `documents_in` - `documents_note` - `documents_out` - `documents_take`


### drink

- `drink_drinking` - `drink_idle`


### drunk

- `drunk_gestic_01` - `drunk_gestic_02`


### gestic

- `gestic_laugh_extreme` - `gestic_laugh_loud` - `gestic_laugh_low` - `gestic_listen_accept_01` - `gestic_listen_accept_02` - `gestic_listen_accept_03` - `gestic_listen_accept_04` - `gestic_listen_accept_05` - `gestic_listen_angry_01` - `gestic_listen_deny_01` - `gestic_listen_deny_02` - `gestic_listen_deny_03` - `gestic_listen_deny_04` - `gestic_listen_deny_05` - `gestic_listen_deny_06` - `gestic_listen_excited_01` - `gestic_listen_left_01` - `gestic_listen_nervous_01` - `gestic_listen_neutral_01` - `gestic_listen_neutral_02` - `gestic_listen_neutral_03` - `gestic_listen_relaxed_01` - `gestic_listen_right_01` - `gestic_listen_sad_01` - `gestic_listen_self-assured_01` - `gestic_presentation_left_01` - `gestic_presentation_right_01` - `gestic_shrug_01` - `gestic_shrug_02` - `gestic_talk_angry_01` - `gestic_talk_cool` - `gestic_talk_excited_01` - `gestic_talk_excited_02` - `gestic_talk_femalestressed_01` - `gestic_talk_left_01` - `gestic_talk_nervous_01` - `gestic_talk_nervous_02` - `gestic_talk_neutral_01` - `gestic_talk_neutral_02` - `gestic_talk_neutral_03` - `gestic_talk_relaxed_01` - `gestic_talk_relaxed_02` - `gestic_talk_right_01` - `gestic_talk_sad_01` - `gestic_talk_self-assured_01` - `gestic_talk_self-assured_02` - `gestic_thoughtful_01`


### headphones

- `headphones_idle`


### hold

- `hold_bag_idle` - `hold_bag_idle_01` - `hold_bag_listen` - `hold_bag_talk`


### idle

- `idle_angry_01` - `idle_angry_02` - `idle_breathe_01` - `idle_breathe_02` - `idle_breathe_03` - `idle_cough_01` - `idle_cough_02` - `idle_drunk_01` - `idle_drunk_02` - `idle_dust_01` - `idle_dust_02` - `idle_finger nail_01` - `idle_look_around_01` - `idle_look_around_02` - `idle_look_around_03` - `idle_move_01` - `idle_move_leg_01` - `idle_nervous_01` - `idle_nervous_02` - `idle_nervous_03` - `idle_neutral_01` - `idle_neutral_02` - `idle_neutral_03` - `idle_neutral_04` - `idle_neutral_05` - `idle_neutral_06` - `idle_neutral_07` - `idle_neutral_08` - `idle_neutral_09` - `idle_roll_head_01` - `idle_roll_head_02` - `idle_scratch_head_01` - `idle_scratch_head_02` - `idle_shake_arms_01` - `idle_shake_leg_01` - `idle_stretch_arms_01` - `idle_touch_face_01` - `idle_touch_face_02` - `idle_touch_hair_01` - `idle_waiting_01` - `idle_waiting_02` - `idle_yawn_01`


### invite

- `invite_sit`


### knock

- `knock_door`


### listen

- `listen_door`


### moderate

- `moderate_01` - `moderate_02`


### newspaper

- `newspaper_arm_idle` - `newspaper_hand_idle`


### sit

- `sit_chair_breathe_01` - `sit_chair_gestic_shrug_01` - `sit_chair_gestic_shrug_02` - `sit_chair_gestic_thoughtful` - `sit_chair_idle_cough` - `sit_chair_idle_dust` - `sit_chair_idle_finger nail` - `sit_chair_idle_look_around` - `sit_chair_idle_nervous_01` - `sit_chair_idle_neutral_01` - `sit_chair_idle_neutral_02` - `sit_chair_idle_relaxed_01` - `sit_chair_idle_roll_head` - `sit_chair_idle_scratch_head` - `sit_chair_idle_touch_face` - `sit_chair_idle_touch_hair` - `sit_chair_idle_waiting_01` - `sit_chair_idle_waiting_02` - `sit_chair_idle_yawn` - `sit_table_breathe_01` - `sit_table_gestic_shrug_01` - `sit_table_gestic_shrug_02` - `sit_table_gestic_thoughtful` - `sit_table_idle_cough` - `sit_table_idle_dust` - `sit_table_idle_look_around` - `sit_table_idle_nervous_01` - `sit_table_idle_neutral_01` - `sit_table_idle_neutral_02` - `sit_table_idle_relaxed_01` - `sit_table_idle_roll_head` - `sit_table_idle_scratch_head` - `sit_table_idle_stretch arms` - `sit_table_idle_touch_face` - `sit_table_idle_touch_hair` - `sit_table_idle_waiting_01` - `sit_table_idle_yawn`


### take

- `take_picture`


### trolley

- `trolley_idle` - `trolley_listen` - `trolley_talk`


### try

- `try_door_inwards` - `try_door_outwards`


### umbrella

- `umbrella_idle_01` - `umbrella_idle_02` - `umbrella_listen_01` - `umbrella_talk_01`


### wave

- `wave_01` - `wave_02`


### work

- `work_mid` - `work_table`


