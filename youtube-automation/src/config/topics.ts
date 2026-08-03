import { Topic } from "../types.js";

/**
 * Public-domain classic rhymes. Lyrics are the traditional text, not
 * LLM-generated — never let a model "rewrite" a nursery rhyme, since it will
 * confidently invent lines that aren't the real (safe, familiar) song.
 */
const classics: Topic[] = [
  {
    slug: "twinkle-twinkle",
    title: "Twinkle Twinkle Little Star",
    lyrics: [
      "Twinkle, twinkle, little star,",
      "How I wonder what you are!",
      "Up above the world so high,",
      "Like a diamond in the sky.",
      "Twinkle, twinkle, little star,",
      "How I wonder what you are!",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "lullaby", "toddler songs", "baby music"],
  },
  {
    slug: "wheels-on-the-bus",
    title: "The Wheels on the Bus",
    lyrics: [
      "The wheels on the bus go round and round,",
      "round and round, round and round.",
      "The wheels on the bus go round and round,",
      "all through the town.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "wheels on the bus", "toddler songs", "kids songs"],
  },
  {
    slug: "old-macdonald",
    title: "Old MacDonald Had a Farm",
    lyrics: [
      "Old MacDonald had a farm, E-I-E-I-O,",
      "And on his farm he had a cow, E-I-E-I-O.",
      "With a moo-moo here and a moo-moo there,",
      "Here a moo, there a moo, everywhere a moo-moo.",
      "Old MacDonald had a farm, E-I-E-I-O.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "old macdonald", "animal sounds", "farm animals"],
  },
  {
    slug: "itsy-bitsy-spider",
    title: "The Itsy Bitsy Spider",
    lyrics: [
      "The itsy bitsy spider climbed up the water spout.",
      "Down came the rain and washed the spider out.",
      "Out came the sun and dried up all the rain,",
      "And the itsy bitsy spider climbed up the spout again.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "itsy bitsy spider", "finger play", "toddler songs"],
  },
  {
    slug: "row-row-row-your-boat",
    title: "Row, Row, Row Your Boat",
    lyrics: [
      "Row, row, row your boat,",
      "gently down the stream.",
      "Merrily, merrily, merrily, merrily,",
      "life is but a dream.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "row row row your boat", "toddler songs"],
  },
  {
    slug: "baa-baa-black-sheep",
    title: "Baa, Baa, Black Sheep",
    lyrics: [
      "Baa, baa, black sheep, have you any wool?",
      "Yes sir, yes sir, three bags full.",
      "One for the master, one for the dame,",
      "And one for the little boy who lives down the lane.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "baa baa black sheep", "toddler songs"],
  },
  {
    slug: "head-shoulders-knees-toes",
    title: "Head, Shoulders, Knees and Toes",
    lyrics: [
      "Head, shoulders, knees and toes, knees and toes,",
      "Head, shoulders, knees and toes, knees and toes,",
      "And eyes and ears and mouth and nose,",
      "Head, shoulders, knees and toes, knees and toes.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "head shoulders knees and toes", "action songs"],
  },
  {
    slug: "five-little-ducks",
    title: "Five Little Ducks",
    lyrics: [
      "Five little ducks went out one day,",
      "over the hills and far away.",
      "Mother duck said, 'Quack, quack, quack, quack,'",
      "but only four little ducks came back.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "five little ducks", "counting songs"],
  },
  {
    slug: "hickory-dickory-dock",
    title: "Hickory Dickory Dock",
    lyrics: [
      "Hickory dickory dock,",
      "the mouse ran up the clock.",
      "The clock struck one,",
      "the mouse ran down,",
      "hickory dickory dock.",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "hickory dickory dock", "toddler songs"],
  },
  {
    slug: "abc-song",
    title: "The ABC Song",
    lyrics: [
      "A B C D E F G,",
      "H I J K L M N O P,",
      "Q R S, T U V,",
      "W X, Y and Z.",
      "Now I know my ABCs,",
      "next time won't you sing with me?",
    ],
    ageRange: "0-3",
    tags: ["nursery rhyme", "abc song", "alphabet for kids", "learning songs"],
  },
];

/**
 * Original simple concept videos (not tied to a specific song) — the LLM
 * fills in the scene breakdown for these, since there's no fixed lyric to
 * preserve.
 */
const concepts: Topic[] = [
  {
    slug: "learn-colors-1",
    title: "Learn Colors with Fruits and Balloons",
    concept:
      "A short, slow-paced video introducing 5 basic colors (red, yellow, blue, green, orange) using one familiar object per color, with the color name said clearly and repeated.",
    ageRange: "0-3",
    tags: ["learn colors", "toddler learning", "baby educational video"],
  },
  {
    slug: "counting-1-to-10",
    title: "Counting 1 to 10 with Friendly Animals",
    concept:
      "Count from 1 to 10 using one cute animal per number, each number shown large on screen and spoken clearly, with a short pause for the child to repeat.",
    ageRange: "0-3",
    tags: ["counting for kids", "numbers 1 to 10", "toddler learning"],
  },
  {
    slug: "shapes-for-toddlers-1",
    title: "Learning Shapes: Circle, Square, Triangle, Star",
    concept:
      "Introduce four basic shapes one at a time using a simple everyday object shaped like each, naming the shape clearly and repeating it twice.",
    ageRange: "0-3",
    tags: ["learn shapes", "toddler learning", "shapes for kids"],
  },
  {
    slug: "animal-sounds-1",
    title: "Animal Sounds for Babies: Farm Edition",
    concept:
      "Show 6 familiar farm animals one at a time, say the animal's name, then play/say its sound, with a brief pause before moving to the next animal.",
    ageRange: "0-3",
    tags: ["animal sounds", "farm animals for kids", "baby learning video"],
  },
];

export const topicCatalog: Topic[] = [...classics, ...concepts];
