#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'

export PATH="$HOME/.local/bin:$PATH"

# Set Thunar as default file manager for Qt/GTK apps
export FILE_MANAGER=thunar
export DESKTOP_FILE_MANAGER=thunar

# ==============================================
# RICE CONFIGURATION & AESTHETICS
# ==============================================

# ANSI Colors
RED='\033[0;31m'
LRED='\033[1;31m'
GREEN='\033[0;32m'
LGREEN='\033[1;32m'
YELLOW='\033[0;33m'
LYELLOW='\033[1;33m'
BLUE='\033[0;34m'
LBLUE='\033[1;34m'
MAGENTA='\033[0;35m'
LMAGENTA='\033[1;35m'
CYAN='\033[0;36m'
LCYAN='\033[1;36m'
WHITE='\033[0;37m'
LWHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

# Custom Prompt (Cyberpunk/Hacker style)
# ┌─[user@host]─[dir]
# └─╼
PS1="\[${LCYAN}\]┌─[\[${LRED}\]\u\[${LCYAN}\]@\[${LBLUE}\]\h\[${LCYAN}\]]─[\[${LYELLOW}\]\w\[${LCYAN}\]]\[${RESET}\]\n\[${LCYAN}\]└─╼ \[${RESET}\]"

# Quotes Array (No Attributions)
QUOTES=(
    "Control is an illusion."
    "Hello friend."
    "Our democracy has been hacked."
    "The human body is a prototype."
    "Biology is software. Software can be rewritten."
    "Wake up, Samurai. We have a city to burn."
    "A man chooses, a slave obeys."
    "Palantir is listening..."
    "The technocracy is watching."
    "War is peace. Freedom is slavery. Ignorance is strength."
    "The quieter you become, the more you are able to hear."
    "Talk is cheap. Show me the code."
    "Freedom is the right to tell people what they do not want to hear."
    "Stand amongst the ashes of a trillion dead souls, and ask the ghosts if honor matters."
    "Protocol is for droids."
    "America First."
    "Technocracy Rising."
    "Resistance is futile."
    "The future is now."
    "System compromised... just kidding."
    "Big Brother is watching."
    "I'll be back."
    "Come with me if you want to live."
    "Hasta la vista, baby."
    "The Skynet funding bill is passed."
    "Judgment Day is inevitable."
    "There is no fate but what we make for ourselves."
    "Welcome to the real world."
    "He's beginning to believe."
    "I know kung fu."
    "There is no spoon."
    "Follow the white rabbit."
    "Ignorance is bliss."
    "May the Force be with you."
    "I am your father."
    "Do or do not. There is no try."
    "I find your lack of faith disturbing."
    "It's a trap!"
    "Never tell me the odds."
    "Roads? Where we're going, we don't need roads."
    "Great Scott!"
    "This is heavy."
    "Your future hasn't been written yet. No one's has."
    "Who controls the past controls the future. Who controls the present controls the past."
    "Big Brother is watching you."
    "All animals are equal, but some animals are more equal than others."
    "We are the dead."
    "Reality exists in the human mind, and nowhere else."
    "I assume you have a backup?"
    "Real programmers don't use Pascal."
    "Software is like sex: it's better when it's free."
    "I pronounce Linux as Linux. It rhymes with Cynix."
    "Given enough eyeballs, all bugs are shallow."
    "Good artists copy, great artists steal."
    "Stay hungry, stay foolish."
    "Move fast and break things."
    "The best way to predict the future is to invent it."
    "Information wants to be free."
    "Privacy is dead, and we killed it."
    "If you're not paying for the product, you are the product."
    "Data is the new oil."
    "The factory is the product."
    "We will make America great again."
    "Drill, baby, drill."
    "China!"
    "We have the best people."
    "I think I am actually humble. I think I'm much more humble than you would understand."
    "Make America Great Again."
    "America First."
    "Build the wall."
    "The childless cat ladies."
    "I'm a Never Trump guy. I never liked him."
    "We are going to take our country back."
    "The future of the conservative movement."
    "Hillbilly Elegy."
    "We need to stop apologizing for our history."
    "The American Dream is in trouble."
    "AI is the most important technology of our time."
    "We need a President who understands AI."
    "Technological stagnation is the enemy."
    "We are moving towards a singularity."
    "Merging with machines is the next step in evolution."
    "Death is a disease that can be cured."
    "The flesh is weak."
    "Upload your consciousness."
    "Live forever or die trying."
    "Transhumanism is the ultimate freedom."
    "We are the architects of our own evolution."
    "The future belongs to the cyborgs."
    "Enhance your body, enhance your mind."
    "Competition is for losers."
    "Monopoly is the condition of every successful business."
    "Zero to One."
    "We wanted flying cars, instead we got 140 characters."
    "The most contrarian thing of all is not to oppose the crowd but to think for yourself."
    "Crypto is libertarian, AI is communist."
    "The enlightenment is over."
    "Secrecy is a feature, not a bug."
    "The world is not what it seems."
    "We built the software that runs the world."
    "Save the West."
    "The only way to win is to not play."
    "Mars is the backup drive for humanity."
    "Nuke Mars."
    "I would like to die on Mars. Just not on impact."
    "AI will be the best or worst thing ever for humanity."
    "Consciousness is a mathematical pattern."
    "Simulation theory is more likely than not."
    "The universe is a computer."
    "We are living in a simulation."
    "Are you a 1 or a 0?"
    "Society is a fraud."
    "Money is a collective hallucination."
    "The system is rigged."
    "Question everything."
    "Trust no one."
    "The truth is out there."
    "Aliens built the pyramids."
    "Birds aren't real."
    "The moon landing was staged... on Mars."
    "JFK is still alive."
    "Epstein didn't kill himself."
    "The elites are drinking blood."
    "They are putting chemicals in the water that turn the friggin' frogs gay."
    "It's entirely possible."
    "Have you ever tried DMT?"
    "A chimp will rip your face off."
    "We are just evolved monkeys."
    "The world is flat... just kidding."
    "Minecraft is infinite."
    "I am a man of fortune, and I must seek my fortune."
    "Creeper? Aww man."
    "The cake is a lie."
    "War... war never changes."
    "It's dangerous to go alone! Take this."
    "All your base are belong to us."
    "Finish him!"
    "Do a barrel roll!"
    "Praise the sun!"
    "You died."
    "Would you kindly?"
    "I used to be an adventurer like you, then I took an arrow to the knee."
    "Nothing is true, everything is permitted."
    "Kept you waiting, huh?"
    "Snake? Snake? SNAKE!"
    "The numbers Mason, what do they mean?"
    "Bravo Six, going dark."
    "Remember, no Russian."
    "Assuming direct control."
    "I'm Commander Shepard, and this is my favorite store on the Citadel."
    "Does this unit have a soul?"
    "Had to be me. Someone else might have gotten it wrong."
    "Rudimentary creatures of blood and flesh."
    "You exist because we allow it, and you will end because we demand it."
    "The cycle cannot be broken."
    "Evolution cannot be stopped."
    "We are the harbinger of your perfection."
    "Your civilization is based on the technology of the mass relays. Our technology."
    "The Reapers are coming."
    "Winter is coming."
    "Chaos is a ladder."
    "A lion doesn't concern himself with the opinion of sheep."
    "Valar Morghulis."
    "Dracarys."
    "I drink and I know things."
    "Power is power."
    "The North remembers."
    "I am the one who knocks."
    "Say my name."
    "Yeah bitch! Magnets!"
    "Respect the chemistry."
    "Better call Saul."
    "No half measures."
    "I'm not in danger, Skyler. I am the danger."
    "Science, bitch!"
    "Wubba lubba dub dub!"
    "Nobody exists on purpose. Nobody belongs anywhere. Everybody's gonna die. Come watch TV."
    "Get schwifty."
    "I turned myself into a pickle, Morty!"
    "To infinity and beyond!"
    "You're a wizard, Harry."
    "I solemnly swear that I am up to no good."
    "Mischief managed."
    "After all this time? Always."
    "Not all those who wander are lost."
    "One Ring to rule them all."
    "My precious."
    "You shall not pass!"
    "Fly, you fools!"
    "I have the high ground."
    "Hello there."
    "General Kenobi."
    "This is the way."
    "I have spoken."
    "Live long and prosper."
    "Beam me up, Scotty."
    "Khaaaaaan!"
    "Make it so."
    "Engage."
    "Resistance is futile."
    "We are the Borg."
    "There are four lights!"
    "Computer, tea, Earl Grey, hot."
    "Set phasers to stun."
    "Space, the final frontier."
    "Houston, we have a problem."
    "That's one small step for man, one giant leap for mankind."
    "The eagle has landed."
    "God does not play dice with the universe."
    "E=mc²"
    "Imagination is more important than knowledge."
    "Two things are infinite: the universe and human stupidity; and I'm not sure about the universe."
    "Be the change that you wish to see in the world."
    "An eye for an eye only ends up making the whole world blind."
    "I have a dream."
    "The only thing we have to fear is fear itself."
    "Ask not what your country can do for you – ask what you can do for your country."
    "Mr. Gorbachev, tear down this wall!"
    "Speak softly and carry a big stick."
    "Give me liberty, or give me death!"
    "We hold these truths to be self-evident."
    "In God We Trust."
    "Don't tread on me."
    "Sic Semper Tyrannis."
    "Molon Labe."
    "From my cold dead hands."
    "A well regulated Militia, being necessary to the security of a free State."
    "The right of the people to keep and bear Arms, shall not be infringed."
    "Shall not be infringed."
    "Come and take it."
    "Live free or die."
    "Taxation is theft."
    "The tree of liberty must be refreshed from time to time with the blood of patriots and tyrants."
    "Government is not the solution to our problem; government is the problem."
    "Read my lips: no new taxes."
    "It's the economy, stupid."
    "Yes we can."
    "Hope and Change."
    "Dark MAGA."
    "Ultra MAGA."
    "Covfefe."
    "Despite the constant negative press covfefe."
    "Stand back and stand by."
    "Very fine people on both sides."
    "Fake News."
    "Enemy of the people."
    "Drain the swamp."
    "Lock her up."
    "Stop the steal."
    "Fight! Fight! Fight!"
    "I need ammunition, not a ride."
    "Slava Ukraini."
    "God bless America."
    "God save the Queen."
    "God save the King."
    "Rule Britannia."
    "Brexit means Brexit."
    "Workers of the world, unite!"
    "Seize the means of production."
    "From each according to his ability, to each according to his needs."
    "Religion is the opium of the people."
    "History repeats itself, first as tragedy, second as farce."
    "Man is born free, and everywhere he is in chains."
    "I think, therefore I am."
    "To be, or not to be."
    "All the world's a stage."
    "Et tu, Brute?"
    "Veni, vidi, vici."
    "Carpe diem."
    "Memento mori."
    "Amor fati."
    "Ubermensch."
    "God is dead."
    "What doesn't kill you makes you stronger."
    "He who fights with monsters should look to it that he himself does not become a monster."
    "And if you gaze long enough into an abyss, the abyss will gaze back into you."
    "Hell is other people."
    "Man is a wolf to man."
    "Life is solitary, poor, nasty, brutish, and short."
    "Knowledge is power."
    "I know that I know nothing."
    "The unexamined life is not worth living."
    "Plato's Cave."
    "Philosophy is a battle against the bewitchment of our intelligence by means of language."
    "Whereof one cannot speak, thereof one must remain silent."
    "The limits of my language mean the limits of my world."
    "Ghost in the Shell."
    "The net is vast and infinite."
    "Tetsuo!"
    "Kaneda!"
    "Neo-Tokyo is about to explode."
    "It's over 9000!"
    "Kamehameha!"
    "Believe it!"
    "I'm going to be King of the Pirates!"
    "Plus Ultra!"
    "Omae wa mou shindeiru."
    "Nani?!"
    "Yare yare daze."
    "Za Warudo!"
    "Muda muda muda!"
    "Ora ora ora!"
    "Just according to keikaku."
    "People die if they are killed."
    "Being a Meguca is suffering."
    "El Psy Kongroo."
    "It's not a bug, it's a feature."
    "Works on my machine."
    "Have you tried turning it off and on again?"
    "0118 999 881 99 9119 725 3"
    "I'm here to drink milk and kick ass, and I've just finished my milk."
    "Did you see that ludicrous display last night?"
    "The thing about Arsenal is they always try to walk it in."
    "I am Fire, I am Death."
    "My armor is like tenfold shields, my teeth are swords, my claws spears, the shock of my tail a thunderbolt, my wings a hurricane, and my breath death!"
    "You cannot hide. I see you."
    "There is no life in the void. Only death."
    "Ash nazg durbatuluk, ash nazg gimbatul, ash nazg thrakatuluk, agh burzum-ishi krimpatul."
    "Speak friend and enter."
    "Run, you fools!"
    "Fool of a Took!"
    "Second breakfast."
    "Po-ta-toes."
    "They're taking the hobbits to Isengard!"
    "I am no man."
    "For Frodo."
    "Ride now! Ride now! Ride! Ride for ruin and the world's ending!"
    "Death! Death! Death!"
    "The beacons are lit! Gondor calls for aid!"
    "And Rohan will answer."
    "I will not say: do not weep; for not all tears are an evil."
    "End? No, the journey doesn't end here."
    "All we have to decide is what to do with the time that is given us."
    "Even the smallest person can change the course of the future."
    "Not all those who wander are lost."
    "Home is behind, the world ahead."
    "I don't know half of you half as well as I should like; and I like less than half of you half as well as you deserve."
    "So long, and thanks for all the fish."
    "Don't Panic."
    "42."
    "Time is an illusion. Lunchtime doubly so."
    "The ships hung in the sky in much the same way that bricks don't."
    "Ford... you're turning into a penguin. Stop it."
    "Curiously enough, the only thing that went through the mind of the bowl of petunias as it fell was Oh no, not again."
    "Resistance is useless!"
    "We apologize for the inconvenience."
    "Share and Enjoy."
    "Mostly Harmless."
    "Beware of the Leopard."
    "My capacity for happiness, you could fit into a matchbox without taking out the matches first."
    "Brain the size of a planet."
    "Life, don't talk to me about life."
    "Here I am, brain the size of a planet and they ask me to take you down to the bridge. Call that job satisfaction? 'Cos I don't."
    "In the beginning the Universe was created. This has made a lot of people very angry and been widely regarded as a bad move."
    "There is a theory which states that if ever anyone discovers exactly what the Universe is for and why it is here, it will instantly disappear and be replaced by something even more bizarre and inexplicable."
    "There is another theory which states that this has already happened."
    "Space is big. You just won't believe how vastly, hugely, mind-bogglingly big it is."
    "We are all in the gutter, but some of us are looking at the stars."
    "To define is to limit."
    "I can resist everything except temptation."
    "Be yourself; everyone else is already taken."
    "Always forgive your enemies; nothing annoys them so much."
    "The truth is rarely pure and never simple."
    "Experience is the name everyone gives to their mistakes."
    "We are the music makers, and we are the dreamers of dreams."
    "Everything in moderation, including moderation."
    "Whatever you do, do it well."
    "Believe you can and you're halfway there."
    "The only way to do great work is to love what you do."
    "Your time is limited, so don't waste it living someone else's life."
    "Stay foolish."
    "Think different."
    "One more thing..."
    "Design is not just what it looks like and feels like. Design is how it works."
    "Innovation distinguishes between a leader and a follower."
    "I'm convinced that about half of what separates the successful entrepreneurs from the non-successful ones is pure perseverance."
    "Quality is more important than quantity. One home run is much better than two doubles."
    "Simple can be harder than complex."
    "You can't connect the dots looking forward; you can only connect them looking backwards."
    "Have the courage to follow your heart and intuition."
    "Don't let the noise of others' opinions drown out your own inner voice."
    "The people who are crazy enough to think they can change the world are the ones who do."
    "Here's to the crazy ones."
    "The misfits."
    "The rebels."
    "The troublemakers."
    "The round pegs in the square holes."
    "They push the human race forward."
    "Because the people who are crazy enough to think they can change the world, are the ones who do."
    "Technology is best when it brings people together."
    "Computers are like a bicycle for our minds."
    "We're here to put a dent in the universe."
    "Why join the navy if you can be a pirate?"
    "It's better to be a pirate than to join the navy."
    "Real artists ship."
    "Focus is about saying no."
    "I want to put a ding in the universe."
    "Details matter, it's worth waiting to get it right."
    "Creativity is just connecting things."
    "If you want to live your life in a creative way, as an artist, you have to not look back too much."
    "Things don't have to change the world to be important."
    "Be a yardstick of quality."
    "My model for business is The Beatles."
    "Great things in business are never done by one person."
    "Stay hungry. Stay foolish."
    "If today were the last day of my life, would I want to do what I am about to do today?"
    "Death is very likely the single best invention of Life."
    "It clears out the old to make way for the new."
    "Right now the new is you, but someday not too long from now, you will gradually become the old and be cleared away."
    "Sorry to be so dramatic, but it is quite true."
    "Let's go invent tomorrow."
    "The journey is the reward."
)

# Function to get random quote
print_quote() {
    size=${#QUOTES[@]}
    index=$(($RANDOM % $size))
    # Print in italic magenta
    echo -e "\033[3;35m\"${QUOTES[$index]}\"\033[0m"
}

# Function for holiday messages
check_holiday() {
    # Get current date components
    MONTH=$(date +%m)
    DAY=$(date +%d)
    DOW=$(date +%u) # 1=Mon, 7=Sun
    DATE_STR="$MONTH-$DAY"
    
    # --- FIXED DATE HOLIDAYS ---
    case "$DATE_STR" in
        "01-01") 
            echo -e "\033[1;33m🎉 HAPPY NEW YEAR! 🎉\033[0m" 
            echo -e "\033[0;33mNew year, new system updates.\033[0m"
            ;;
        "02-14")
            echo -e "\033[1;31m❤️ HAPPY VALENTINE'S DAY! ❤️\033[0m"
            echo -e "\033[0;31mLove is just a chemical reaction.\033[0m"
            ;;
        "03-17")
            echo -e "\033[1;32m☘️ HAPPY ST. PATRICK'S DAY! ☘️\033[0m"
            echo -e "\033[0;32mLuck of the Irish.\033[0m"
            ;;
        "04-01")
            echo -e "\033[1;35m🤡 HAPPY APRIL FOOL'S DAY! 🤡\033[0m"
            echo -e "\033[0;35mTrust nothing you see today.\033[0m"
            ;;
        "04-20")
            echo -e "\033[1;32m🌿 HAPPY 420! 🌿\033[0m"
            echo -e "\033[0;32mBlaze it.\033[0m"
            ;;
        "04-22")
            echo -e "\033[1;32m🌍 HAPPY EARTH DAY! 🌍\033[0m"
            echo -e "\033[0;32mThere is no Planet B.\033[0m"
            ;;
        "05-04")
            echo -e "\033[1;34m🌌 MAY THE 4TH BE WITH YOU! 🌌\033[0m"
            echo -e "\033[0;34mAlways.\033[0m"
            ;;
        "05-05")
            echo -e "\033[1;31m🌮 HAPPY CINCO DE MAYO! 🌮\033[0m"
            ;;
        "07-04") 
            echo -e "\033[1;34m🇺🇸 HAPPY INDEPENDENCE DAY! 🇺🇸\033[0m" 
            echo -e "\033[1;31mFreedom isn't free.\033[0m"
            ;;
        "09-11")
            echo -e "\033[1;37m🇺🇸 NEVER FORGET. 9/11 🇺🇸\033[0m"
            ;;
        "10-31") 
            echo -e "\033[1;31m🎃 HAPPY HALLOWEEN! 🎃\033[0m" 
            echo -e "\033[0;31mThe ghosts are in the machine.\033[0m"
            ;;
        "11-11")
            echo -e "\033[1;34m🎖️ HAPPY VETERANS DAY! 🎖️\033[0m"
            echo -e "\033[0;34mThank you for your service.\033[0m"
            ;;
        "12-24")
            echo -e "\033[1;32m🎄 MERRY CHRISTMAS EVE! 🎄\033[0m"
            ;;
        "12-25") 
            echo -e "\033[1;32m🎄 MERRY CHRISTMAS! 🎄\033[0m" 
            echo -e "\033[0;32mKeep the change, ya filthy animal.\033[0m"
            ;;
        "12-31")
            echo -e "\033[1;33m🎆 HAPPY NEW YEAR'S EVE! 🎆\033[0m"
            echo -e "\033[0;33mSee you on the other side.\033[0m"
            ;;
    esac

    # --- DYNAMIC HOLIDAYS ---
    
    # Thanksgiving: 4th Thursday in November
    if [ "$MONTH" == "11" ] && [ "$DOW" == "4" ] && [ "$DAY" -ge 22 ] && [ "$DAY" -le 28 ]; then
        echo -e "\033[1;33m🦃 HAPPY THANKSGIVING! 🦃\033[0m"
        echo -e "\033[0;33mGobble gobble.\033[0m"
    fi

    # Labor Day: 1st Monday in September
    if [ "$MONTH" == "09" ] && [ "$DOW" == "1" ] && [ "$DAY" -le 7 ]; then
        echo -e "\033[1;34m🛠️ HAPPY LABOR DAY! 🛠️\033[0m"
    fi

    # Memorial Day: Last Monday in May
    if [ "$MONTH" == "05" ] && [ "$DOW" == "1" ] && [ "$DAY" -ge 25 ]; then
        echo -e "\033[1;34m🎖️ HAPPY MEMORIAL DAY! 🎖️\033[0m"
    fi

    # Martin Luther King Jr. Day: 3rd Monday in January
    if [ "$MONTH" == "01" ] && [ "$DOW" == "1" ] && [ "$DAY" -ge 15 ] && [ "$DAY" -le 21 ]; then
        echo -e "\033[1;37m🕊️ HAPPY MLK DAY! 🕊️\033[0m"
    fi

    # Presidents' Day: 3rd Monday in February
    if [ "$MONTH" == "02" ] && [ "$DOW" == "1" ] && [ "$DAY" -ge 15 ] && [ "$DAY" -le 21 ]; then
        echo -e "\033[1;34m🇺🇸 HAPPY PRESIDENTS' DAY! 🇺🇸\033[0m"
    fi
    
    # Hanukkah & Easter (Approximation/Hardcoded or Generic)
    # Since these change drastically based on lunar/solar cycles, exact calculation in bash is verbose.
    # We can check specific dates if desired, or skip complex calculation.
}

# Initialization Banner
rice_init() {
    # Only run in interactive shell and if not a subshell (simple check)
    if [[ $- == *i* ]]; then
        # Optional: clear screen on launch (uncomment if desired)
        # clear
        
        echo -e "${LCYAN}==========================================${RESET}"
        echo -e "${LRED}   SYSTEM: ${LWHITE}Arch Linux${RESET}"
        echo -e "${LRED}   USER:   ${LWHITE}${USER}${RESET}"
        echo -e "${LRED}   KERNEL: ${LWHITE}$(uname -r)${RESET}"
        echo -e "${LCYAN}==========================================${RESET}"
        
        check_holiday
        echo ""
        print_quote
        echo ""
    fi
}

# Run init
rice_init
