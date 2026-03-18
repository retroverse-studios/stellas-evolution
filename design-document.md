# Stella's Evolution: Game Design Document

## 1. Game Concept

"Stella's Evolution" is a four-part game series that explores the concept of a minimalist puzzle platformer across different generations of Atari 2600 technology. Inspired by Mike Bithell's "Thomas Was Alone," the series follows the journey of simple geometric shapes with distinct personalities and abilities as they navigate an abstract digital world.

Starting with the most constrained implementation (4K) and progressing through increasing technological capabilities (8K, 16K, and finally ARM coprocessor), the project demonstrates how gameplay and storytelling can evolve with technology while maintaining the core essence of character-driven puzzle-platforming.

### 1.1 Core Philosophy

The minimalist visual style of "Thomas Was Alone" is perfectly suited to the Atari 2600's limitations. By embracing these constraints rather than fighting them, "Stella's Evolution" aims to deliver a compelling experience that feels authentic to both the original game and the Atari platform, while also showing how the same core concept can evolve with technology.

### 1.2 Game Goals

- Create a series of challenging puzzle-platformers that rewards skill and forethought
- Tell a progressively richer story through level design and character abilities
- Demonstrate how meaningful gameplay experiences can exist within various technical constraints
- Honor both the spirit of "Thomas Was Alone" and the evolution of Atari development
- Bridge classic and modern indie game development approaches

## 2. Series Overview

### 2.1 "Stella Was Alone" (4K)
The first entry focuses on the essentials with just two geometric characters navigating simple yet challenging levels. With extreme memory constraints, this game emphasizes pure gameplay mechanics over narrative.

### 2.2 "Stella Was Together" (8K)
The second entry introduces a third character and expands the gameplay possibilities with more complex puzzles and basic narrative elements between levels.

### 2.3 "Stella's Journey" (16K)
The third entry features enhanced abilities, more sophisticated puzzles, and an expanded narrative that begins to reveal more of the characters' personalities and story.

### 2.4 "Stella Meets Thomas" (ARM)
The final entry utilizes modern ARM coprocessor technology to create a crossover experience that bridges classic Atari gaming with the visual style and narrative depth of the original "Thomas Was Alone."

## 3. Gameplay Mechanics

### 3.1 Character Abilities

Across the series, characters evolve with increasingly sophisticated abilities:

#### "Stella Was Alone" (4K)
- **Tall Rectangle**
   - Highest jump height
   - Slowest horizontal movement
   - Can reach high platforms

- **Flat Rectangle**
   - Low jump height
   - Fastest horizontal movement
   - Can squeeze under low overhangs

#### "Stella Was Together" (8K)
Adds:
- **Square**
   - Balanced jump height and movement speed
   - Most versatile character
   - Perfect size for medium gaps

#### "Stella's Journey" (16K)
Enhanced abilities:
- **Tall Rectangle**: Adds wall climbing
- **Square**: Adds double jump
- **Flat Rectangle**: Adds brief hover

#### "Stella Meets Thomas" (ARM)
- All previous characters with fluid animations
- New crossover characters inspired by "Thomas Was Alone"
- Complex ability combinations and interactions

### 3.2 Core Mechanics

The mechanics evolve across the series:

#### "Stella Was Alone" (4K)
- **Character Switching**: Players press Down+Fire to toggle between two characters
- **Platforming**: Basic jump and movement mechanics
- **Gravity**: Standard downward gravity
- **Level Completion**: Both characters must reach their goals

#### "Stella Was Together" (8K)
- **Character Cycling**: Players cycle through three characters
- **Enhanced Physics**: Improved collision detection
- **Character Interaction**: Characters can stand on each other
- **Narrative Elements**: Simple text screens between levels

#### "Stella's Journey" (16K)
- **Ability Combinations**: Special moves using enhanced abilities
- **Environment Interaction**: Moving platforms, buttons, etc.
- **Advanced Physics**: Variable jump heights, momentum
- **Extended Narrative**: More detailed story elements

#### "Stella Meets Thomas" (ARM)
- **Fluid Physics**: Modern physics engine capabilities
- **Character Dialogue**: Visual indicators of character thoughts
- **Dynamic Environments**: Responsive level elements
- **Meta-Narrative**: Commentary on game development evolution

## 4. Level Design

### 4.1 Level Structure

The complexity and scope of levels increase across the series:

#### "Stella Was Alone" (4K)
- 4-5 tightly designed levels
- Simple platform arrangements
- Each level focuses on a single concept
- Limited color palette for mood

#### "Stella Was Together" (8K)
- 8-10 more complex levels
- Multi-room designs
- Puzzles requiring character cooperation
- More varied color schemes

#### "Stella's Journey" (16K)
- 12-15 sophisticated levels
- Multi-stage puzzles
- Environmental hazards and moving elements
- Dynamic color shifts for narrative

#### "Stella Meets Thomas" (ARM)
- 15-20 richly detailed levels
- Complex environmental storytelling
- Multiple paths and secrets
- Advanced visual effects and lighting

### 4.2 Progression

Each game features a carefully designed difficulty curve:

- **Introduction**: Teach basic mechanics
- **Early Levels**: Simple application of core concepts
- **Middle Levels**: Combination of multiple mechanics
- **Later Levels**: Complex puzzles requiring mastery
- **Final Levels**: Creative application of all learned skills

## 5. Visual Design

### 5.1 Character Representation

#### "Stella Was Alone" (4K)
- **Tall Rectangle**: Red (NTSC value $30), tall and narrow
- **Flat Rectangle**: Green (NTSC value $C0), wide and short
- Simple player sprites with solid colors

#### "Stella Was Together" (8K)
- Adds **Square**: Blue (NTSC value $80), equal height and width
- More detailed sprite designs
- Character-specific movement animations

#### "Stella's Journey" (16K)
- Enhanced character designs with subtle details
- More animation frames
- Visual effects for abilities

#### "Stella Meets Thomas" (ARM)
- Fluid animations
- Particle effects
- Dynamic lighting
- Character expressions through subtle shape changes

### 5.2 Environment

The environmental design grows richer across the series:

#### "Stella Was Alone" (4K)
- Solid color platforms
- Simple backgrounds
- Minimalist goals

#### "Stella Was Together" (8K)
- More varied platform types
- Simple background patterns
- Animated goal areas

#### "Stella's Journey" (16K)
- Multiple platform materials
- Parallax background elements
- Environmental animations

#### "Stella Meets Thomas" (ARM)
- Rich textured environments
- Dynamic lighting effects
- Particle systems
- Weather and atmospheric effects

## 6. Audio Design

### 6.1 Sound Effects

Audio complexity increases with each iteration:

#### "Stella Was Alone" (4K)
- **Jump**: Simple upward tone
- **Land**: Brief low tone
- **Goal**: Simple completion sound

#### "Stella Was Together" (8K)
- Character-specific jump sounds
- Interaction sounds
- More complex goal fanfares

#### "Stella's Journey" (16K)
- Full suite of action sounds
- Environmental audio cues
- Narrative moment accents

#### "Stella Meets Thomas" (ARM)
- Rich sound design
- Multiple simultaneous effects
- Positional audio
- Adaptive effects based on gameplay

### 6.2 Background Audio

Background audio evolves throughout the series:

#### "Stella Was Alone" (4K)
- Minimal ambient tones, if possible

#### "Stella Was Together" (8K)
- Simple melodic patterns
- Level-specific tones

#### "Stella's Journey" (16K)
- Dynamic audio that responds to progress
- Emotional accents for narrative moments

#### "Stella Meets Thomas" (ARM)
- Full soundtrack
- Adaptive music
- Character themes
- Narrative-driven audio cues

## 7. Scope

### 7.1 Game Content

The project consists of four distinct games with increasing scope:

#### "Stella Was Alone" (4K)
- **Characters**: 2 characters (Tall Rectangle, Flat Rectangle)
- **Number of Levels**: 4-5 total
- **Tutorial Levels**: 2 (one for each character)
- **Standard Levels**: 2-3 of increasing complexity

#### "Stella Was Together" (8K)
- **Characters**: 3 characters (adds Square)
- **Number of Levels**: 8-10 total
- **Tutorial Levels**: 3 (one for each character)
- **Standard Levels**: 5-7 of increasing complexity

#### "Stella's Journey" (16K)
- **Characters**: 3 characters with enhanced abilities
- **Number of Levels**: 12-15 total
- **Tutorial Levels**: 3 (one for each character)
- **Standard Levels**: 9-12 with advanced puzzles

#### "Stella Meets Thomas" (ARM)
- **Characters**: 5+ characters including crossover elements
- **Number of Levels**: 15-20 total
- **Tutorial Levels**: 5+ (introducing new mechanics)
- **Standard Levels**: 10-15 with sophisticated puzzles

### 7.2 Feature Priority

Each version has its own feature priorities:

#### "Stella Was Alone" (4K)
1. **Core Mechanics**: Basic movement, jumping, character switching
2. **Level Design**: Simple puzzles that showcase basic character abilities
3. **Physics**: Basic collision detection and response
4. **Visuals**: Minimalist character and platform graphics
5. **Audio**: Very basic sound effects

#### "Stella Was Together" (8K)
1. **Expanded Mechanics**: Enhanced movement physics, third character
2. **Level Design**: More complex puzzles requiring character cooperation
3. **Physics**: More accurate collision and interaction
4. **Visuals**: Character-specific visual identities
5. **Audio**: Character-specific sound effects
6. **Narrative**: Basic storytelling elements

#### "Stella's Journey" (16K)
1. **Advanced Mechanics**: Refined physics, enhanced character abilities
2. **Level Design**: Complex, multi-stage puzzles
3. **Physics**: Sophisticated interaction between characters
4. **Visuals**: Enhanced visual feedback and effects
5. **Audio**: Atmospheric sound elements
6. **Narrative**: Extended storyline with more context

#### "Stella Meets Thomas" (ARM)
1. **Modern Mechanics**: Fluid physics, multiple abilities per character
2. **Level Design**: Rich, intricate puzzle environments
3. **Physics**: Modern physics engine capabilities
4. **Visuals**: Dynamic lighting, particle effects, smooth animation
5. **Audio**: Multi-channel sound design
6. **Narrative**: Full storyline with meta-commentary on game development

## 8. Success Criteria

Each game in the series has its own success criteria:

### "Stella Was Alone" (4K)
1. Fits entirely within 4K ROM
2. Two fully functional characters with distinct abilities
3. Complete 4-5 level progression
4. Stable frame rate and collision detection
5. Captures the essence of minimalist platforming

### "Stella Was Together" (8K)
1. Successful implementation of bankswitching
2. Three well-balanced characters
3. More sophisticated level design within 8K
4. Basic narrative elements implemented
5. Character-specific audio and visual elements

### "Stella's Journey" (16K)
1. Advanced bankswitching with optimized memory usage
2. Enhanced abilities that expand gameplay
3. Rich level designs with complex puzzles
4. Extended narrative that develops characters
5. Atmospheric elements that enhance immersion

### "Stella Meets Thomas" (ARM)
1. Successful integration of ARM coprocessor with Atari hardware
2. Fluid, modern gameplay that remains true to the series
3. Meaningful crossover elements with the original inspiration
4. Visual and audio quality that bridges retro and modern
5. Meta-narrative that comments on game development evolution

## 9. Development Timeline

### Phase 1: "Stella Was Alone" (4K) - Q3 2025
- **Prototype (4-6 weeks)**
  - Implement basic movement and jumping for two characters
  - Create simple test level
  - Establish core engine architecture

- **Core Features (4 weeks)**
  - Implement character switching
  - Develop collision detection system
  - Create level loading system

- **Content Development (4 weeks)**
  - Design and implement 4-5 game levels
  - Add minimal sound effects
  - Create title screen and game flow

- **Polish and Testing (2 weeks)**
  - Optimize code for the 4K constraint
  - Fine-tune level difficulty
  - Test on actual hardware

### Phase 2: "Stella Was Together" (8K) - Q1 2026
- **Engine Expansion (6 weeks)**
  - Implement bankswitching
  - Add third character
  - Enhance physics system

- **Feature Development (4 weeks)**
  - Create more complex level structures
  - Implement character-specific sounds
  - Add basic narrative elements

- **Content Creation (6 weeks)**
  - Design and implement 8-10 game levels
  - Create interstitial story screens
  - Enhance visual feedback

- **Testing and Refinement (4 weeks)**
  - Optimize for 8K ROM
  - Balance difficulty curve
  - Improve game flow

### Phase 3: "Stella's Journey" (16K) - Q4 2026
- **Advanced Engine (8 weeks)**
  - Implement 16K bankswitching
  - Create enhanced physics system
  - Improve character abilities

- **Enhanced Features (6 weeks)**
  - Develop atmospheric audio
  - Implement richer visual feedback
  - Create expanded narrative system

- **Extended Content (8 weeks)**
  - Design and implement 12-15 levels
  - Create more complex puzzles
  - Develop narrative arc

- **Final Polish (4 weeks)**
  - Optimize performance
  - Final difficulty balancing
  - Comprehensive testing

### Phase 4: "Stella Meets Thomas" (ARM) - Q3 2027
- **Modern Framework (10 weeks)**
  - Set up ARM coprocessor development environment
  - Create interface between ARM and Atari hardware
  - Develop modern physics engine

- **Advanced Features (8 weeks)**
  - Implement fluid animation system
  - Create dynamic lighting effects
  - Develop multi-channel audio
  - Design crossover character system

- **Rich Content (10 weeks)**
  - Design and implement 15-20 sophisticated levels
  - Create meta-narrative elements
  - Develop advanced visual effects

- **Final Integration (6 weeks)**
  - Optimize ARM/Atari interface
  - Fine-tune performance
  - Final balancing and testing

## 10. Post-Release Plans

- Community engagement through documented development process
- Potential physical cartridge production for all four games
- Technical writeups to share knowledge with the Atari development community
- Possible expansion with additional levels as downloadable content
- Consideration of ports to other retro platforms
