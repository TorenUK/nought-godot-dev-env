-- ========================================
-- HEALTHY HABITS GAME DATABASE SCHEMA
-- ========================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

-- ========================================
-- ENUMS
-- ========================================
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended', 'deleted');
CREATE TYPE habit_type AS ENUM ('quit', 'build', 'maintain');
CREATE TYPE habit_category AS ENUM ('substance', 'health', 'exercise', 'mental_health', 'social', 'productivity', 'other');
CREATE TYPE neurodivergent_type AS ENUM ('adhd', 'autism', 'anxiety', 'depression', 'ocd', 'other', 'none');
CREATE TYPE mood_level AS ENUM ('very_low', 'low', 'neutral', 'good', 'very_good');
CREATE TYPE trigger_severity AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE friendship_status AS ENUM ('pending', 'accepted', 'blocked', 'declined');
CREATE TYPE post_type AS ENUM ('text', 'image', 'milestone', 'mood_check', 'support_request');
CREATE TYPE notification_type AS ENUM ('friend_request', 'milestone', 'support', 'reminder', 'system');
CREATE TYPE room_type AS ENUM ('bedroom', 'living_room', 'kitchen', 'bathroom', 'office', 'meditation', 'exercise', 'garden', 'custom');
CREATE TYPE activity_status AS ENUM ('sleeping', 'exercising', 'meditating', 'working', 'socializing', 'self_care', 'offline');

-- ========================================
-- CORE USER TABLES
-- ========================================

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email CITEXT UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    avatar_url VARCHAR(500),
    bio TEXT,
    date_of_birth DATE,
    timezone VARCHAR(50) DEFAULT 'UTC',
    status user_status DEFAULT 'active',
    is_verified BOOLEAN DEFAULT FALSE,
    privacy_level INTEGER DEFAULT 1, -- 1=private, 2=friends, 3=public
    last_active TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE NULL
);

-- User profiles with neurodivergent considerations
CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    neurodivergent_types neurodivergent_type[] DEFAULT '{}',
    accessibility_needs JSONB DEFAULT '{}', -- High contrast, reduced motion, etc.
    notification_preferences JSONB DEFAULT '{}',
    reminder_settings JSONB DEFAULT '{}',
    crisis_contacts JSONB DEFAULT '{}',
    emergency_resources JSONB DEFAULT '{}',
    onboarding_completed BOOLEAN DEFAULT FALSE,
    current_activity activity_status DEFAULT 'offline',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ========================================
-- HABIT TRACKING TABLES
-- ========================================

-- Habits definition
CREATE TABLE habits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    type habit_type NOT NULL,
    category habit_category NOT NULL,
    target_frequency INTEGER DEFAULT 1, -- Daily frequency
    target_duration INTEGER, -- In minutes
    is_primary BOOLEAN DEFAULT FALSE, -- Main sobriety habit
    start_date DATE NOT NULL,
    end_date DATE, -- For temporary habits
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Daily habit tracking
CREATE TABLE habit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    completed BOOLEAN DEFAULT FALSE,
    completion_time TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    mood_before mood_level,
    mood_after mood_level,
    difficulty_level INTEGER CHECK (difficulty_level >= 1 AND difficulty_level <= 10),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(habit_id, date)
);

-- Milestones and achievements
CREATE TABLE milestones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    milestone_type VARCHAR(50) NOT NULL, -- 'days', 'weeks', 'months', 'custom'
    milestone_value INTEGER NOT NULL,
    achieved_at TIMESTAMP WITH TIME ZONE NOT NULL,
    celebrated BOOLEAN DEFAULT FALSE,
    shared_publicly BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Relapse tracking 
CREATE TABLE relapses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    trigger_description TEXT,
    mood_at_time mood_level,
    support_sought BOOLEAN DEFAULT FALSE,
    notes TEXT,
    learned_from TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Triggers tracking
CREATE TABLE triggers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    severity trigger_severity NOT NULL,
    category VARCHAR(50),
    coping_strategies TEXT[],
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Trigger occurrences
CREATE TABLE trigger_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trigger_id UUID NOT NULL REFERENCES triggers(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    intensity INTEGER CHECK (intensity >= 1 AND intensity <= 10),
    coping_used TEXT[],
    outcome TEXT,
    mood_before mood_level,
    mood_after mood_level,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ========================================
-- SOCIAL FEATURES TABLES
-- ========================================

-- Friendships
CREATE TABLE friendships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    addressee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status friendship_status DEFAULT 'pending',
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    responded_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(requester_id, addressee_id),
    CHECK (requester_id != addressee_id)
);

-- Best friends (limit 3)
CREATE TABLE best_friends (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, friend_id),
    CHECK (user_id != friend_id)
);

-- Constraint to limit best friends to 3
CREATE OR REPLACE FUNCTION check_best_friends_limit()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT COUNT(*) FROM best_friends WHERE user_id = NEW.user_id) >= 3 THEN
        RAISE EXCEPTION 'User can have maximum 3 best friends';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER best_friends_limit_trigger
    BEFORE INSERT ON best_friends
    FOR EACH ROW EXECUTE FUNCTION check_best_friends_limit();

-- Posts/Social feed
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type post_type NOT NULL,
    content TEXT,
    image_urls TEXT[],
    mood mood_level,
    milestone_id UUID REFERENCES milestones(id),
    visibility INTEGER DEFAULT 2, -- 1=private, 2=friends, 3=public
    is_support_request BOOLEAN DEFAULT FALSE,
    tags TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Comments on posts
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    parent_comment_id UUID REFERENCES comments(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Post reactions (likes, support, etc.)
CREATE TABLE post_reactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction_type VARCHAR(20) NOT NULL, -- 'like', 'support', 'celebrate', 'heart'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(post_id, user_id, reaction_type)
);

-- ========================================
-- BUILDING/SAFE SPACE TABLES
-- ========================================

-- User spaces (houses/safe spaces)
CREATE TABLE user_spaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_primary BOOLEAN DEFAULT TRUE,
    privacy_level INTEGER DEFAULT 1, -- 1=private, 2=friends, 3=public
    grid_size_x INTEGER DEFAULT 20,
    grid_size_y INTEGER DEFAULT 20,
    theme_id UUID, -- Reference to themes table
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Rooms within spaces
CREATE TABLE rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    space_id UUID NOT NULL REFERENCES user_spaces(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    type room_type NOT NULL,
    x_position INTEGER NOT NULL,
    y_position INTEGER NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    color_scheme JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Furniture and decorations
CREATE TABLE furniture_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    item_type VARCHAR(50) NOT NULL, -- 'chair', 'table', 'plant', etc.
    name VARCHAR(100),
    x_position INTEGER NOT NULL,
    y_position INTEGER NOT NULL,
    rotation INTEGER DEFAULT 0,
    scale_factor DECIMAL(3,2) DEFAULT 1.0,
    color_customization JSONB DEFAULT '{}',
    unlock_condition VARCHAR(100), -- Achievement or milestone required
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Space visits (when friends visit)
CREATE TABLE space_visits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    space_id UUID NOT NULL REFERENCES user_spaces(id) ON DELETE CASCADE,
    visitor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    visited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    duration_minutes INTEGER,
    left_message TEXT
);

-- ========================================
-- NOTIFICATIONS TABLES
-- ========================================

-- Notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type notification_type NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}', -- Additional data for the notification
    is_read BOOLEAN DEFAULT FALSE,
    is_push_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    read_at TIMESTAMP WITH TIME ZONE
);

-- ========================================
-- SYSTEM TABLES
-- ========================================

-- Achievements definitions
CREATE TABLE achievements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    icon_url VARCHAR(500),
    category VARCHAR(50),
    criteria JSONB NOT NULL, -- Conditions to unlock
    reward_data JSONB DEFAULT '{}', -- Virtual items, decorations, etc.
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User achievements
CREATE TABLE user_achievements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    achievement_id UUID NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    achieved_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    progress_data JSONB DEFAULT '{}',
    UNIQUE(user_id, achievement_id)
);

-- App settings and configuration
CREATE TABLE app_settings (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ========================================
-- INDEXES FOR PERFORMANCE
-- ========================================

-- User indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_last_active ON users(last_active);

-- Habit tracking indexes
CREATE INDEX idx_habits_user_id ON habits(user_id);
CREATE INDEX idx_habits_type ON habits(type);
CREATE INDEX idx_habits_is_active ON habits(is_active);
CREATE INDEX idx_habit_logs_habit_id ON habit_logs(habit_id);
CREATE INDEX idx_habit_logs_date ON habit_logs(date);
CREATE INDEX idx_habit_logs_user_date ON habit_logs(user_id, date);

-- Social features indexes
CREATE INDEX idx_friendships_requester ON friendships(requester_id);
CREATE INDEX idx_friendships_addressee ON friendships(addressee_id);
CREATE INDEX idx_friendships_status ON friendships(status);
CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX idx_posts_visibility ON posts(visibility);
CREATE INDEX idx_comments_post_id ON comments(post_id);

-- Building system indexes
CREATE INDEX idx_user_spaces_user_id ON user_spaces(user_id);
CREATE INDEX idx_rooms_space_id ON rooms(space_id);
CREATE INDEX idx_furniture_room_id ON furniture_items(room_id);

-- Notification indexes
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- ========================================
-- FUNCTIONS AND TRIGGERS
-- ========================================

-- Update timestamp function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to relevant tables
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_profiles_updated_at BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_habits_updated_at BEFORE UPDATE ON habits
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_triggers_updated_at BEFORE UPDATE ON triggers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_friendships_updated_at BEFORE UPDATE ON friendships
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_posts_updated_at BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_spaces_updated_at BEFORE UPDATE ON user_spaces
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to calculate sobriety streak
CREATE OR REPLACE FUNCTION calculate_sobriety_streak(p_user_id UUID, p_habit_id UUID)
RETURNS INTEGER AS $$
DECLARE
    streak_count INTEGER := 0;
    check_date DATE := CURRENT_DATE;
    has_log BOOLEAN;
BEGIN
    LOOP
        SELECT EXISTS(
            SELECT 1 FROM habit_logs 
            WHERE habit_id = p_habit_id 
            AND user_id = p_user_id 
            AND date = check_date 
            AND completed = TRUE
        ) INTO has_log;
        
        IF NOT has_log THEN
            EXIT;
        END IF;
        
        streak_count := streak_count + 1;
        check_date := check_date - INTERVAL '1 day';
    END LOOP;
    
    RETURN streak_count;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- INITIAL DATA SETUP
-- ========================================

-- Default achievements
INSERT INTO achievements (name, description, icon_url, category, criteria) VALUES
('First Day', 'Completed your first day of sobriety', '/icons/first-day.png', 'milestone', '{"type": "days", "value": 1}'),
('One Week Strong', 'One week of maintaining your habit', '/icons/one-week.png', 'milestone', '{"type": "days", "value": 7}'),
('One Month Milestone', 'Thirty days of consistent progress', '/icons/one-month.png', 'milestone', '{"type": "days", "value": 30}'),
('Social Butterfly', 'Made your first friend connection', '/icons/social.png', 'social', '{"type": "friends", "value": 1}'),
('Home Builder', 'Created your first safe space room', '/icons/home.png', 'building', '{"type": "rooms", "value": 1}'),
('Support Giver', 'Supported 10 friends in their journey', '/icons/support.png', 'social', '{"type": "support_given", "value": 10}');

-- Default app settings
INSERT INTO app_settings (key, value, description, is_public) VALUES
('max_best_friends', '3', 'Maximum number of best friends allowed', true),
('default_privacy_level', '1', 'Default privacy level for new users', false),
('milestone_celebration_enabled', 'true', 'Enable milestone celebrations', true),
('crisis_resources_enabled', 'true', 'Enable crisis resources feature', true);

-- ========================================
-- VIEWS FOR COMMON QUERIES
-- ========================================

-- User dashboard view
CREATE VIEW user_dashboard AS
SELECT 
    u.id,
    u.username,
    u.display_name,
    up.current_activity,
    up.neurodivergent_types,
    COUNT(DISTINCT f.id) as friend_count,
    COUNT(DISTINCT bf.id) as best_friend_count,
    COUNT(DISTINCT h.id) as active_habits
FROM users u
LEFT JOIN user_profiles up ON u.id = up.user_id
LEFT JOIN friendships f ON (u.id = f.requester_id OR u.id = f.addressee_id) AND f.status = 'accepted'
LEFT JOIN best_friends bf ON u.id = bf.user_id
LEFT JOIN habits h ON u.id = h.user_id AND h.is_active = TRUE
WHERE u.status = 'active'
GROUP BY u.id, u.username, u.display_name, up.current_activity, up.neurodivergent_types;

-- Recent activity feed view
CREATE VIEW recent_activity_feed AS
SELECT 
    p.id,
    p.user_id,
    u.username,
    u.display_name,
    u.avatar_url,
    p.type,
    p.content,
    p.mood,
    p.created_at,
    COUNT(DISTINCT pr.id) as reaction_count,
    COUNT(DISTINCT c.id) as comment_count
FROM posts p
JOIN users u ON p.user_id = u.id
LEFT JOIN post_reactions pr ON p.id = pr.post_id
LEFT JOIN comments c ON p.id = c.post_id
WHERE p.visibility >= 2 AND u.status = 'active'
GROUP BY p.id, p.user_id, u.username, u.display_name, u.avatar_url, p.type, p.content, p.mood, p.created_at
ORDER BY p.created_at DESC;