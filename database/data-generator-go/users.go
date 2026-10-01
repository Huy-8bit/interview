package main

import (
	"context"
	"fmt"
	"math/rand/v2"
	"strconv"
	"strings"
)

var firstNames = strings.Fields("James Mary John Patricia Robert Jennifer Michael Linda William Elizabeth David Barbara Richard Susan Joseph Jessica Thomas Sarah Charles Karen Christopher Nancy Daniel Lisa Matthew Betty Anthony Sandra Mark Ashley Donald Kimberly Steven Emily Paul Donna Andrew Michelle Joshua Carol Kenneth Amanda Kevin Melissa Brian Deborah George Stephanie Timothy Rebecca Ronald Sharon Edward Laura Jason Cynthia Jeffrey Kathleen Ryan Amy Jacob Angela Gary Shirley Nicholas Anna Eric Brenda Jonathan Pamela Stephen Emma Larry Nicole Justin Helen Scott Samantha Brandon Katherine Benjamin Christine Samuel Debra Gregory Rachel Frank Catherine Alexander Carolyn Raymond Janet Patrick Ruth Jack Maria Dennis Heather Jerry Diane Tyler Virginia Aaron Julie Henry Joyce Douglas Victoria Peter Olivia Adam Kelly Nathan Christina Zachary Lauren Walter Joan Kyle Evelyn Harold Judith Carl Megan Arthur Cheryl Gerald Andrea Roger Hannah Keith Martha Jeremy Jacqueline Terry Frances Lawrence Gloria Sean Ann Christian Teresa Albert Kathryn Joe Sara Ethan Janice Austin Jean Jesse Alice Willie Madison Billy Doris Bryan Abigail Bruce Julia Jordan Judy Ralph Grace Roy Denise Noah Amber Dylan Marilyn Eugene Beverly Wayne Danielle Alan Theresa Juan Sophia Louis Marie Russell Diana Gabriel Natalie Randy Brittany Vincent Irene Philip Charlotte Bobby Rose Johnny Alexis Bradley Kayla Alex Jane")
var lastNames = strings.Fields("Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin Lee Perez Thompson White Harris Sanchez Clark Ramirez Lewis Robinson Walker Young Allen King Wright Scott Torres Nguyen Hill Flores Green Adams Nelson Baker Hall Rivera Campbell Mitchell Carter Roberts Gomez Phillips Evans Turner Diaz Parker Cruz Edwards Collins Reyes Stewart Morris Morales Murphy Cook Rogers Gutierrez Ortiz Morgan Cooper Peterson Bailey Reed Kelly Howard Ramos Kim Cox Ward Richardson Watson Brooks Chavez Wood James Bennett Gray Mendoza Ruiz Hughes Price Alvarez Castillo Sanders Patel Myers Long Ross Foster Jimenez Powell Jenkins Perry Russell Sullivan Bell Coleman Butler Henderson Barnes Gonzales Fisher Vasquez Simmons Romero Jordan Patterson Alexander Hamilton Graham Reynolds Griffin Wallace Moreno West Cole Hayes Bryant Herrera Gibson Ellis Tran Medina Aguilar Stevens Murray Ford Castro Marshall Owens Harrison Fernandez Mcdonald Woods Washington Kennedy Wells Vargas Henry Chen Freeman Webb Tucker Guzman Burns Crawford Olson Simpson Porter Hunter Gordon Mendez Silva Shaw Snyder Mason Dixon Munoz Hunt Hicks Holmes Palmer Wagner Black Robertson Boyd Rose Stone Salazar Fox Warren Mills Meyer Rice Schmidt Garza Daniels Ferguson Nichols Stephens Soto Weaver Ryan Gardner Payne Grant Dunn Kelley Spencer Hawkins Arnold Pierce Vazquez Hansen Peters Santos Hart Bradley Knight Elliott Cunningham Duncan Armstrong Hudson Carroll Lane Riley Andrews Alvarado Ray Delgado Berry Perkins Hoffman Johnston Matthews Pena Richards Contreras Willis Carpenter Lawrence Sandoval Guerrero George Chapman Rios Estrada Ortega Watkins Greene Nunez Wheeler Valdez Harper Burke Larson Santiago Maldonado Morrison Franklin Carlson Austin Dominguez Carr Lawson Jacobs Obrien Lynch Singh Vega Bishop Montgomery Oliver Jensen Harvey Williamson Gilbert Dean Sims Espinoza Howell Li Wong Walsh Lawson Pham Huynh Hoang Le Vo Dang Do Bui Duong")
var streets = strings.Fields("Oak Maple Pine Cedar Elm Washington Lake Hill Sunset Park Main River Forest Valley Highland Willow Walnut Cherry Lincoln Madison Jefferson Jackson Adams Franklin")

type geo struct {
	city, state, country string
	weight               int
}

var usCities = []geo{{"New York", "NY", "US", 16}, {"Los Angeles", "CA", "US", 12}, {"Chicago", "IL", "US", 8}, {"Houston", "TX", "US", 7}, {"Phoenix", "AZ", "US", 5}, {"Philadelphia", "PA", "US", 5}, {"San Antonio", "TX", "US", 4}, {"San Diego", "CA", "US", 4}, {"Dallas", "TX", "US", 4}, {"San Jose", "CA", "US", 3}, {"Austin", "TX", "US", 3}, {"Seattle", "WA", "US", 3}, {"Denver", "CO", "US", 3}, {"Boston", "MA", "US", 3}, {"Miami", "FL", "US", 3}, {"Atlanta", "GA", "US", 3}, {"Portland", "OR", "US", 2}}
var intlCities = []geo{{"Ho Chi Minh City", "", "VN", 22}, {"Hanoi", "", "VN", 15}, {"Da Nang", "", "VN", 4}, {"Toronto", "ON", "CA", 10}, {"Vancouver", "BC", "CA", 6}, {"London", "", "GB", 12}, {"Manchester", "", "GB", 4}, {"Berlin", "", "DE", 6}, {"Munich", "", "DE", 4}, {"Paris", "", "FR", 6}, {"Sydney", "NSW", "AU", 6}, {"Tokyo", "", "JP", 7}, {"Singapore", "", "SG", 5}}

type address struct {
	Recipient string `json:"recipient_name"`
	Phone     any    `json:"phone"`
	Line1     string `json:"line1"`
	Line2     any    `json:"line2"`
	City      string `json:"city"`
	State     any    `json:"state"`
	Postal    string `json:"postal_code"`
	Country   string `json:"country_code"`
}

func pickGeo(r *rand.Rand) geo {
	pool := usCities
	if chance(r, .15) {
		pool = intlCities
	} else if chance(r, .3) {
		return geo{fmt.Sprintf("%s %s %d", pick(r, streets), pick(r, []string{"Falls", "Creek", "Springs", "Heights"}), r.IntN(30)), pick(r, usCities).state, "US", 1}
	}
	w := make([]int, len(pool))
	for i, v := range pool {
		w[i] = v.weight
	}
	return pool[weighted(r, w)]
}

// Default addresses are a pure function of seed + user ID. Order workers can
// recreate exactly the same snapshot without millions of SELECTs or a RAM cache.
func (e *engine) userAddress(i int, a int) (string, string, address) {
	r := e.rng(1, uint64(i))
	first, last := pick(r, firstNames), pick(r, lastNames)
	if a > 0 {
		r = e.rng(11+uint64(a), uint64(i))
	}
	g := pickGeo(r)
	v := address{Recipient: first + " " + last, Line1: fmt.Sprintf("%d %s %s", 1+r.IntN(9999), pick(r, streets), pick(r, []string{"St", "Ave", "Rd", "Lane"})), City: g.city, Postal: fmt.Sprintf("%05d", 1000+r.IntN(99000)), Country: g.country}
	if g.state != "" {
		v.State = g.state
	}
	if chance(r, .25) {
		v.Line2 = fmt.Sprintf("Apt %d", 1+r.IntN(999))
	}
	if chance(r, .85) {
		prefix := map[string]string{"US": "1", "CA": "1", "GB": "44", "DE": "49", "FR": "33", "AU": "61", "JP": "81", "SG": "65", "VN": "84"}[g.country]
		v.Phone = fmt.Sprintf("+%s-%03d-%03d-%04d", prefix, 201+r.IntN(789), 200+r.IntN(800), r.IntN(10000))
	}
	return first, last, v
}
func (e *engine) users(ctx context.Context) error {
	r := e.rng(2, 0)
	ids := r.Perm(e.cfg.Users)
	heavy := max(1, int(float64(e.cfg.Users)*e.cfg.HeavyShare))
	e.heavyFlags = make([]bool, e.cfg.Users)
	for j, i := range ids {
		if j < heavy {
			e.heavy = append(e.heavy, int32(i))
			e.heavyFlags[i] = true
		} else {
			e.light = append(e.light, int32(i))
		}
	}
	return e.batches(ctx, "users", e.cfg.Users, func(lo, hi int) *batch {
		u := &copyTable{name: "users", columns: "id,username,email,password_hash,full_name,phone,date_of_birth,gender,status,is_email_verified,loyalty_points,last_login_at,last_login_ip,metadata,created_at,updated_at"}
		a := &copyTable{name: "addresses", columns: "user_id,label,recipient_name,phone,line1,line2,city,state,postal_code,country_code,is_default,created_at"}
		for i := lo; i < hi; i++ {
			r := e.rng(3, uint64(i))
			first, last, addr := e.userAddress(i, 0)
			created := e.userCreated(i)
			username := strings.ToLower(first+"."+last) + strconv.Itoa(i+1)
			email := username + "@" + e.ref.Domains[weighted(r, e.ref.DomainWeights)]
			if chance(r, .05) {
				email = strings.ToUpper(email[:1]) + email[1:]
			}
			lang := e.ref.Languages[weighted(r, e.ref.LanguageWeights)]
			if addr.Country == "VN" {
				lang = "vi"
			}
			meta := map[string]any{"signup_source": e.ref.Sources[weighted(r, e.ref.SourceWeights)], "preferred_language": lang, "marketing_opt_in": chance(r, .45), "preferences": map[string]string{"currency": "USD", "theme": pick(r, []string{"light", "light", "dark"})}}
			if e.heavyFlags[i] && chance(r, .15) {
				meta["tags"] = []string{"vip"}
			}
			if chance(r, .3) {
				meta["newsletter_frequency"] = pick(r, []string{"daily", "weekly", "monthly"})
			}
			if meta["signup_source"] == "referral" {
				meta["referred_by"] = 1 + r.IntN(max(1, i))
			}
			var dob, login, ip, gender any
			updated := created
			if chance(r, .8) {
				dob = stamp(e.cfg.Now.Unix() - int64(18+r.IntN(57))*365*day).Format("2006-01-02")
			}
			if chance(r, .9) {
				updated = between(r, created, e.cfg.Now.Unix())
				login = stamp(updated)
				ip = fmt.Sprintf("%d.%d.%d.%d", 1+r.IntN(223), r.IntN(256), r.IntN(256), 1+r.IntN(254))
			}
			gender = pick(r, []any{"M", "F", "O", nil})
			loyalty := int(r.ExpFloat64() * 250)
			if e.heavyFlags[i] {
				loyalty *= 3
			}
			const alphabet = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
			var hash [53]byte
			for j := range hash {
				hash[j] = alphabet[r.IntN(len(alphabet))]
			}
			u.row(i+1, username, email, "$2b$12$"+string(hash[:]), addr.Recipient, addr.Phone, dob, gender, []string{"ACTIVE", "INACTIVE", "SUSPENDED", "DELETED"}[weighted(r, []int{90, 6, 1, 3})], chance(r, .82), loyalty, login, ip, jsonText(meta), stamp(created), stamp(updated))
			n := 1 + weighted(r, []int{55, 30, 15})
			for j := 0; j < n; j++ {
				v := addr
				if j > 0 {
					_, _, v = e.userAddress(i, j)
				}
				label := "HOME"
				if j > 0 {
					label = pick(r, []string{"WORK", "OTHER"})
				}
				a.row(i+1, label, v.Recipient, v.Phone, v.Line1, v.Line2, v.City, v.State, v.Postal, v.Country, j == 0, stamp(min(created+int64(j)*10*day, e.cfg.Now.Unix())))
			}
		}
		return &batch{tables: []*copyTable{u, a}}
	}, nil)
}
