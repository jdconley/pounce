/** Purrtrait's own word list (design §4.5). Plain lowercase words a six-year-old knows by sight. */

export type Group = "animals" | "food" | "home" | "outside" | "things" | "actions" | "jobs" | "places";
export type Level = "easy" | "tricky";

export const GROUPS: readonly Group[] = ["animals", "food", "home", "outside", "things", "actions", "jobs", "places"];

export type Word = { word: string; group: Group; level: Level };

/** Easy: quick to draw. Tricky: still known by sight, just harder to draw. One comma list per group. */
const EASY: Record<Group, string> = {
  animals:
    "cat,dog,fish,bird,cow,pig,duck,frog,horse,sheep,mouse,rabbit,bear,lion,tiger,monkey,elephant,snake,turtle,bug,bee,spider,chicken,owl,whale,shark,penguin,giraffe,zebra,snail,ant,goat,fox,deer,dolphin,crab",
  food:
    "apple,banana,pizza,cake,cookie,bread,egg,cheese,milk,ice cream,carrot,grapes,orange,strawberry,cherry,lemon,pear,peach,watermelon,corn,hot dog,hamburger,popcorn,pancake,sandwich,candy,cupcake,donut,pie,soup,rice,noodles,tomato,potato,pumpkin,juice",
  home:
    "bed,chair,table,door,window,lamp,clock,couch,spoon,fork,cup,plate,bowl,pillow,blanket,towel,soap,bathtub,mirror,stairs,oven,fridge,broom,key,candle,bookshelf,rug,toothbrush,sink,curtain,television,telephone,roof",
  outside:
    "sun,moon,star,tree,flower,cloud,rain,rainbow,snow,grass,mountain,river,lake,beach,ocean,leaf,rock,hill,bridge,road,path,garden,fence,pond,wave,sand,sky,island,volcano,forest,hole,puddle,mud,wind,campfire",
  things:
    "ball,book,hat,shoe,sock,car,bus,train,boat,airplane,bicycle,balloon,kite,drum,guitar,piano,crayon,pencil,scissors,umbrella,shirt,pants,glasses,ring,crown,gift,bell,camera,phone,computer,robot,doll,teddy bear,blocks,puzzle,backpack",
  actions:
    "run,jump,sleep,eat,drink,swim,dance,sing,read,write,laugh,cry,clap,point,smile,walk,climb,throw,catch,kick,hug,wash,cook,paint,draw,play,sit,stand,fly,push,pull,ride,brush teeth,sneeze,yawn",
  jobs:
    "doctor,teacher,firefighter,farmer,chef,nurse,police officer,baker,dentist,bus driver,painter,singer,pilot,mail carrier,artist,clown,king,queen,cowboy,pirate,builder,librarian,princess,prince,knight,wizard,skater,soccer player,swimmer,runner,writer,dancer,coach,drummer",
  places:
    "school,house,park,zoo,farm,store,hospital,playground,castle,bedroom,bathroom,pool,restaurant,bakery,circus,airport,city,town,barn,shop,museum,theater,bank,jungle,space,street,classroom,backyard,kitchen,garage,playroom,cafe,camp,dock",
};

const TRICKY: Record<Group, string> = {
  animals:
    "octopus,kangaroo,flamingo,hedgehog,porcupine,peacock,squirrel,jellyfish,seahorse,caterpillar,ladybug,dragonfly,crocodile,camel,parrot,bat,skunk,raccoon,hippo,rhino,koala,panda,starfish,lobster,worm,swan,eagle,woodpecker,pelican,walrus,otter,beaver,chameleon,gorilla,donkey,llama,ostrich,tadpole",
  food:
    "spaghetti,pretzel,taco,sushi,waffle,lollipop,pineapple,coconut,broccoli,mushroom,avocado,cereal,jelly,marshmallow,cotton candy,birthday cake,french fries,meatball,burrito,bagel,honey,peanut,pepper,onion,celery,cabbage,lettuce,cucumber,kiwi,mango,pickle,sprinkles,gingerbread,toast,nachos,ice pop",
  home:
    "chimney,fireplace,vacuum,ladder,hammock,bunk bed,closet,drawer,doorbell,doorknob,bubble bath,laundry,dishwasher,microwave,toaster,blender,teapot,kettle,flashlight,night light,hanger,wallpaper,chandelier,rocking chair,bookcase,trash can,shower,washing machine,alarm clock,light bulb,ironing board,mop,sponge,pillowcase,birdhouse,doormat,attic,basement",
  outside:
    "waterfall,lightning,tornado,thunder,shadow,sunrise,sunset,fog,icicle,snowman,snowflake,igloo,cave,desert,tent,swamp,glacier,canyon,meadow,sandcastle,scarecrow,treehouse,bonfire,hurricane,iceberg,rainforest,cactus,footprint,shooting star,pebble,seashell,seaweed,palm tree,windmill,whirlpool,bush,dandelion,sunflower,pinecone,acorn",
  things:
    "trampoline,skateboard,helicopter,submarine,parachute,telescope,microscope,compass,treasure chest,magnet,binoculars,hourglass,yoyo,trumpet,violin,tambourine,xylophone,accordion,harp,fireworks,pinata,roller skates,magic wand,lantern,anchor,bubble,rattle,shovel,wagon,scooter,sled,swing,slide,seesaw,zipper,thermometer,calendar,envelope,stamp,battery,snow globe",
  actions:
    "whisper,tiptoe,juggle,skip,hop,crawl,stretch,tickle,shiver,blink,snore,hiccup,daydream,giggle,tumble,spin,balance,wiggle,squeeze,tie shoes,blow bubbles,share,pretend,march,bow,salute,sweep,dig,knock,wink,whistle,pour,stir,fold,peek,sneak,hide,somersault,cartwheel,bounce,stomp,gallop,splash,melt,freeze",
  jobs:
    "astronaut,scientist,magician,mechanic,plumber,photographer,lifeguard,zookeeper,vet,barber,fisherman,cashier,waiter,gardener,janitor,judge,detective,tailor,carpenter,electrician,window washer,dog walker,ballerina,acrobat,mermaid,superhero,referee,diver,miner,sailor,captain,tour guide,cheerleader,babysitter,news reporter,inventor,train driver,snake charmer",
  places:
    "lighthouse,aquarium,fire station,gas station,carnival,amusement park,movie theater,campsite,farmhouse,pyramid,skyscraper,space station,bus stop,train station,harbor,tunnel,fort,cabin,hotel,post office,laundromat,supermarket,candy store,toy store,ice rink,ski slope,basketball court,mini golf,pet shop,bowling alley,market,parking lot,tree fort,cliff,dentist office,playhouse",
};

function build(): Word[] {
  const out: Word[] = [];
  for (const [level, table] of [
    ["easy", EASY],
    ["tricky", TRICKY],
  ] as const) {
    for (const group of GROUPS) {
      for (const word of table[group].split(",")) out.push({ word, group, level });
    }
  }
  return out;
}

/** Every word. A word's id is its index here, so the order is part of the seeded game: only ever append. */
export const WORDS: readonly Word[] = build();
