"""Static reference data: category tree, brands, product vocab, cities, text pools."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Leaf:
    name: str
    code: str
    nouns: tuple[str, ...]
    price_min: float
    price_max: float
    weight: int  # relative number of products in this category


@dataclass(frozen=True)
class TopCategory:
    name: str
    code: str
    kind: str  # selects the JSONB attribute builder
    brands: tuple[str, ...]
    weight_grams: tuple[int, int]
    leaves: tuple[Leaf, ...] = field(default_factory=tuple)


# 10 top-level + 40 leaf categories = 50 categories
CATEGORY_TREE: tuple[TopCategory, ...] = (
    TopCategory("Electronics", "ELE", "electronics",
                ("Apple", "Samsung", "Sony", "LG", "Xiaomi", "Lenovo", "Dell", "HP", "Asus", "Anker",
                 "Bose", "JBL", "Canon", "Nikon", "Logitech"), (80, 3500), (
        Leaf("Smartphones", "PHN", ("Smartphone", "Phone"), 99, 1599, 3),
        Leaf("Laptops", "LAP", ("Laptop", "Notebook", "Ultrabook"), 299, 3499, 2),
        Leaf("Audio", "AUD", ("Headphones", "Earbuds", "Bluetooth Speaker", "Soundbar"), 15, 599, 3),
        Leaf("Cameras", "CAM", ("Mirrorless Camera", "Action Camera", "Lens", "Webcam"), 39, 2999, 1),
    )),
    TopCategory("Fashion", "FAS", "fashion",
                ("Nike", "Adidas", "Zara", "H&M", "Uniqlo", "Levi's", "Gucci", "Puma", "Under Armour",
                 "Ralph Lauren", "Gap", "Mango"), (100, 2000), (
        Leaf("Men's Clothing", "MEN", ("T-Shirt", "Jeans", "Jacket", "Hoodie", "Polo Shirt", "Chinos"), 9, 199, 4),
        Leaf("Women's Clothing", "WOM", ("Dress", "Blouse", "Skirt", "Cardigan", "Leggings", "Coat"), 9, 249, 5),
        Leaf("Shoes", "SHO", ("Sneakers", "Running Shoes", "Boots", "Sandals", "Loafers"), 19, 299, 3),
        Leaf("Accessories", "ACC", ("Backpack", "Wallet", "Belt", "Sunglasses", "Watch", "Cap"), 5, 499, 3),
    )),
    TopCategory("Home & Kitchen", "HOM", "home",
                ("IKEA", "KitchenAid", "Philips", "Dyson", "Tefal", "Cuisinart", "Nespresso", "Le Creuset",
                 "Muji", "Instant Pot"), (200, 40000), (
        Leaf("Furniture", "FUR", ("Office Chair", "Desk", "Bookshelf", "Sofa", "Coffee Table"), 49, 1999, 1),
        Leaf("Kitchen Appliances", "KIT", ("Blender", "Air Fryer", "Coffee Maker", "Toaster", "Rice Cooker", "Kettle"), 19, 699, 3),
        Leaf("Bedding", "BED", ("Pillow", "Duvet", "Bed Sheet Set", "Mattress Topper"), 15, 399, 2),
        Leaf("Home Decor", "DEC", ("Lamp", "Wall Art", "Vase", "Scented Candle", "Rug", "Mirror"), 5, 499, 2),
    )),
    TopCategory("Beauty", "BEA", "beauty",
                ("L'Oreal", "Estee Lauder", "Clinique", "Neutrogena", "Maybelline", "Dove", "Olay",
                 "The Ordinary", "Chanel", "Dior"), (30, 800), (
        Leaf("Skincare", "SKN", ("Moisturizer", "Serum", "Cleanser", "Sunscreen", "Toner"), 5, 199, 4),
        Leaf("Makeup", "MKP", ("Lipstick", "Foundation", "Mascara", "Eyeshadow Palette"), 4, 89, 3),
        Leaf("Haircare", "HAI", ("Shampoo", "Conditioner", "Hair Oil", "Hair Dryer"), 4, 399, 2),
        Leaf("Fragrance", "FRG", ("Eau de Parfum", "Eau de Toilette", "Body Mist"), 15, 349, 1),
    )),
    TopCategory("Sports & Outdoors", "SPO", "sports",
                ("Nike", "Adidas", "Decathlon", "Garmin", "Wilson", "Coleman", "The North Face", "Yeti",
                 "Specialized", "Columbia"), (100, 25000), (
        Leaf("Fitness", "FIT", ("Yoga Mat", "Dumbbell Set", "Resistance Bands", "Kettlebell", "Treadmill"), 9, 1499, 2),
        Leaf("Camping", "CMP", ("Tent", "Sleeping Bag", "Camping Stove", "Headlamp", "Cooler"), 9, 599, 1),
        Leaf("Cycling", "CYC", ("Road Bike", "Mountain Bike", "Bike Helmet", "Bike Light"), 15, 3999, 1),
        Leaf("Team Sports", "TMS", ("Football", "Basketball", "Tennis Racket", "Badminton Set"), 9, 299, 1),
    )),
    TopCategory("Books", "BOK", "books",
                ("Penguin", "HarperCollins", "O'Reilly", "Macmillan", "Simon & Schuster", "Hachette",
                 "Scholastic", "Wiley"), (150, 1500), (
        Leaf("Fiction", "FIC", ("Novel", "Thriller", "Fantasy Saga", "Mystery"), 5, 39, 3),
        Leaf("Non-fiction", "NFI", ("Biography", "History", "Self-Help Guide", "Cookbook"), 8, 49, 2),
        Leaf("Children's Books", "CHB", ("Picture Book", "Activity Book", "Story Collection"), 4, 29, 2),
        Leaf("Textbooks", "TXT", ("Textbook", "Programming Guide", "Exam Prep Book"), 19, 199, 1),
    )),
    TopCategory("Toys & Games", "TOY", "toys",
                ("LEGO", "Hasbro", "Mattel", "Ravensburger", "Fisher-Price", "Hot Wheels", "Nerf",
                 "Melissa & Doug"), (50, 5000), (
        Leaf("Board Games", "BRD", ("Board Game", "Card Game", "Strategy Game"), 9, 99, 2),
        Leaf("Building Sets", "BLD", ("Building Set", "Construction Kit", "Robot Kit"), 9, 499, 2),
        Leaf("Dolls & Figures", "DOL", ("Doll", "Action Figure", "Plush Toy"), 5, 99, 1),
        Leaf("Puzzles", "PUZ", ("Jigsaw Puzzle", "3D Puzzle", "Brain Teaser"), 5, 59, 1),
    )),
    TopCategory("Grocery", "GRO", "grocery",
                ("Nestle", "Kellogg's", "Lay's", "Coca-Cola", "Starbucks", "Lipton", "Barilla", "Heinz",
                 "Kirkland", "Nature Valley"), (50, 5000), (
        Leaf("Snacks", "SNK", ("Chips", "Granola Bars", "Cookies", "Mixed Nuts", "Chocolate"), 1, 25, 5),
        Leaf("Beverages", "BEV", ("Sparkling Water", "Juice", "Energy Drink", "Soda Pack"), 1, 30, 4),
        Leaf("Coffee & Tea", "COF", ("Ground Coffee", "Coffee Beans", "Green Tea", "Coffee Pods"), 3, 45, 4),
        Leaf("Pantry", "PAN", ("Pasta", "Olive Oil", "Rice", "Pasta Sauce", "Cereal"), 1, 35, 3),
    )),
    TopCategory("Automotive", "AUT", "automotive",
                ("Bosch", "3M", "Michelin", "Castrol", "Garmin", "Thule", "Meguiar's", "Armor All"), (50, 8000), (
        Leaf("Car Electronics", "CEL", ("Dash Cam", "Car Charger", "GPS Navigator", "Phone Mount"), 9, 399, 1),
        Leaf("Tools", "TOL", ("Socket Set", "Jump Starter", "Tire Inflator", "Torque Wrench"), 9, 299, 1),
        Leaf("Car Care", "CCR", ("Car Wax", "Microfiber Towels", "Car Shampoo", "Interior Cleaner"), 4, 59, 1),
        Leaf("Parts", "PRT", ("Wiper Blades", "Air Filter", "Brake Pads", "Motor Oil"), 5, 199, 1),
    )),
    TopCategory("Health", "HEA", "health",
                ("Nature Made", "Centrum", "Optimum Nutrition", "Omron", "Braun", "Garden of Life",
                 "Myprotein", "Oral-B"), (50, 2500), (
        Leaf("Vitamins", "VIT", ("Multivitamin", "Vitamin D3", "Omega-3", "Magnesium"), 5, 59, 3),
        Leaf("Medical Supplies", "MED", ("Blood Pressure Monitor", "Thermometer", "First Aid Kit", "Pulse Oximeter"), 9, 149, 1),
        Leaf("Personal Care", "PER", ("Electric Toothbrush", "Razor", "Water Flosser"), 5, 249, 2),
        Leaf("Sports Nutrition", "SPN", ("Whey Protein", "Creatine", "Pre-Workout", "Protein Bar"), 9, 89, 2),
    )),
)

WAREHOUSES = (
    # code, name, city, country
    ("US-WEST-1", "Los Angeles Fulfillment Center", "Los Angeles", "US"),
    ("US-EAST-1", "New Jersey Fulfillment Center", "Newark", "US"),
    ("US-CENTRAL-1", "Dallas Fulfillment Center", "Dallas", "US"),
    ("EU-CENTRAL-1", "Frankfurt Distribution Hub", "Frankfurt", "DE"),
    ("AP-SOUTHEAST-1", "Singapore Distribution Hub", "Singapore", "SG"),
)

ADJECTIVES = ("Pro", "Ultra", "Classic", "Essential", "Premium", "Lite", "Max", "Smart", "Eco", "Deluxe",
              "Compact", "Signature", "Sport", "Urban", "Everyday", "Advanced", "Mini", "Plus", "Original", "Vintage")
BOOK_WORDS_A = ("Silent", "Hidden", "Last", "Broken", "Golden", "Midnight", "Forgotten", "Wild", "Crimson",
                "Distant", "Little", "Secret", "Practical", "Modern", "Complete", "Effective", "Clean", "Deep")
BOOK_WORDS_B = ("River", "Kingdom", "Garden", "Promise", "Code", "Mountain", "Letters", "Habits", "Empire",
                "Ocean", "Machine", "Journey", "Kitchen", "Mind", "Systems", "Architecture", "Data", "Summer")

COLORS = ("Black", "White", "Silver", "Gray", "Blue", "Red", "Green", "Pink", "Beige", "Navy", "Gold", "Brown")
COLOR_WEIGHTS = (30, 20, 8, 10, 9, 5, 4, 3, 3, 4, 2, 2)
MATERIALS = ("Cotton", "Polyester", "Leather", "Denim", "Wool", "Linen", "Nylon")
HOME_MATERIALS = ("Wood", "Metal", "Plastic", "Glass", "Ceramic", "Fabric", "Bamboo")
CAR_MAKES = ("Toyota", "Honda", "Ford", "BMW", "Tesla", "Hyundai", "Kia", "Mazda", "Volkswagen", "Chevrolet")
BOOK_LANGUAGES = ("English", "Spanish", "French", "German", "Vietnamese", "Japanese")
BOOK_LANGUAGE_WEIGHTS = (82, 5, 4, 3, 4, 2)

PRODUCT_TAGS = ("new", "bestseller", "sale", "eco-friendly", "limited-edition", "premium", "gift-idea",
                "clearance", "exclusive", "trending")
PRODUCT_TAG_WEIGHTS = (10, 6, 12, 5, 2, 5, 6, 4, 2, 4)

FEATURES = ("long-lasting durability", "a minimalist design", "premium materials", "an ergonomic shape",
            "fast charging", "a lightweight build", "eco-friendly packaging", "a two-year warranty",
            "award-winning design", "easy one-hand operation", "a water-resistant finish", "all-day comfort")
BENEFITS = ("Perfect for everyday use.", "A great gift for friends and family.", "Loved by thousands of customers.",
            "Designed for people on the go.", "Built to last for years.", "Easy to clean and maintain.",
            "Ideal for beginners and professionals alike.", "Our best-selling model this season.")

# ---- Geography ---------------------------------------------------------------
# Real big cities get most addresses -> strongly skewed value frequencies
# (compare selectivity of city = 'New York' vs a rare city in the query lab).
US_TOP_CITIES = (
    ("New York", "NY", 16), ("Los Angeles", "CA", 12), ("Chicago", "IL", 8), ("Houston", "TX", 7),
    ("Phoenix", "AZ", 5), ("Philadelphia", "PA", 5), ("San Antonio", "TX", 4), ("San Diego", "CA", 4),
    ("Dallas", "TX", 4), ("San Jose", "CA", 3), ("Austin", "TX", 3), ("Seattle", "WA", 3),
    ("Denver", "CO", 3), ("Boston", "MA", 3), ("Miami", "FL", 3), ("Atlanta", "GA", 3),
    ("Portland", "OR", 2), ("Las Vegas", "NV", 2), ("Nashville", "TN", 2), ("Minneapolis", "MN", 2),
)
INTERNATIONAL_CITIES = (
    # country, city, state/region, weight
    ("VN", "Ho Chi Minh City", None, 22), ("VN", "Hanoi", None, 15), ("VN", "Da Nang", None, 4),
    ("CA", "Toronto", "ON", 10), ("CA", "Vancouver", "BC", 6),
    ("GB", "London", None, 12), ("GB", "Manchester", None, 4),
    ("DE", "Berlin", None, 6), ("DE", "Munich", None, 4),
    ("FR", "Paris", None, 6), ("AU", "Sydney", "NSW", 6), ("AU", "Melbourne", "VIC", 4),
    ("JP", "Tokyo", None, 7), ("JP", "Osaka", None, 3), ("SG", "Singapore", None, 5),
)
INTERNATIONAL_SHARE = 0.15

EMAIL_DOMAINS = ("gmail.com", "yahoo.com", "outlook.com", "icloud.com", "hotmail.com", "proton.me", "example.com")
EMAIL_DOMAIN_WEIGHTS = (45, 14, 14, 8, 7, 3, 9)

SIGNUP_SOURCES = ("web", "ios_app", "android_app", "referral", "facebook_ads", "google_ads")
SIGNUP_SOURCE_WEIGHTS = (35, 22, 20, 8, 8, 7)
LANGUAGES = ("en", "vi", "es", "fr", "de", "ja")
LANGUAGE_WEIGHTS = (68, 12, 7, 5, 4, 4)

COUPONS = ("WELCOME10", "SAVE15", "FREESHIP", "BLACKFRIDAY25", "VIP20", "SUMMER10")
COUPON_WEIGHTS = (30, 20, 25, 10, 5, 10)

# ---- Review text by sentiment -----------------------------------------------
REVIEW_TITLES = {
    "positive": ("Absolutely love it", "Great value for money", "Exceeded my expectations", "Highly recommend",
                 "Five stars", "Works perfectly", "Better than expected", "Would buy again", "Excellent quality"),
    "neutral": ("It's okay", "Decent for the price", "Does the job", "Average product", "Mixed feelings",
                "Not bad, not great"),
    "negative": ("Very disappointed", "Stopped working after a week", "Not as described", "Poor quality",
                 "Waste of money", "Would not recommend", "Arrived damaged"),
}
REVIEW_SENTENCES = {
    "positive": ("The quality is outstanding.", "Shipping was fast and the packaging was great.",
                 "I use it every day and it still looks new.", "Exactly what I was looking for.",
                 "My whole family loves it.", "Setup took less than five minutes.",
                 "Worth every penny.", "Customer service was very helpful.", "Already ordered a second one."),
    "neutral": ("It works, but the build feels a bit cheap.", "Delivery took longer than expected.",
                "Good enough for occasional use.", "The color is slightly different from the photos.",
                "Instructions could be clearer.", "Fine for the price, nothing special."),
    "negative": ("It broke after a few days.", "The size was completely wrong.",
                 "Customer support never answered my emails.", "It does not match the description at all.",
                 "The box was damaged and parts were missing.", "I returned it and I'm still waiting for the refund.",
                 "Battery life is terrible."),
}
