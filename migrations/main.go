package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
	_ "github.com/lib/pq"
	"github.com/pressly/goose/v3"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	_ "github.com/lib/pq"
)

var (
	flags = flag.NewFlagSet("goose", flag.ExitOnError)
	dir   = flags.String("dir", ".", "directory with migration files")
)

type TenantClient struct {
	ID         uint   `gorm:"primaryKey"`
	SchemaName string `gorm:"column:schema_name"`
}

// func main() {

// 	flags.Parse(os.Args[1:])
// 	args := flags.Args()

// 	if len(args) < 3 {
// 		flags.Usage()
// 		return
// 	}

// 	dbstring, command := args[1], args[2]
// 	// Connect to the database
// 	db, err := goose.OpenDBWithDriver("postgres", dbstring)
// 	if err != nil {
// 		log.Fatalf("goose: failed to open DB: %v\n", err)
// 	}
// 	_, err = db.Exec("SET SEARCH_PATH = public;")
// 	if err != nil {
// 		log.Fatalf("goose: failed to open DB: %v\n", err)
// 	}

// 	fmt.Println("connected to postgres")
// 	var tenants []TenantClient
// 	rows, err := db.Query("SELECT id, schema_name from tenant_client")
// 	for rows.Next() {
// 		var tenantID int
// 		var schemaName string
// 		err := rows.Scan(&tenantID, &schemaName)
// 		if err != nil {
// 			log.Fatalf(err.Error())
// 		}
// 		tenants = append(tenants, TenantClient{ID: uint(tenantID), SchemaName: schemaName})
// 	}
// 	rows.Close()

// 	fmt.Println(command)

// 	for _, tenant := range tenants {
// 		fmt.Printf("Workspace ID: %d, Name: %s\n", tenant.ID, tenant.SchemaName)

// 		sqlCommand := fmt.Sprintf("CREATE SCHEMA IF NOT EXISTS %s", tenant.SchemaName)

// 		// Execute the raw SQL command
// 		_, err := db.Exec(sqlCommand)
// 		if err != nil {
// 			panic("failed to execute raw SQL command")
// 		}

// 		fmt.Println("dbstring--", dbstring)
// 		query := fmt.Sprintf("SET SEARCH_PATH = %s;", tenant.SchemaName)
// 		_, err = db.Exec(query)
// 		if err != nil {
// 			log.Fatalf("goose: failed to open DB: %v\n", err)
// 		}

// 		arguments := []string{}
// 		if len(args) > 3 {
// 			arguments = append(arguments, args[3:]...)
// 		}
// 		if err := goose.RunContext(context.Background(), command, db, *dir, arguments...); err != nil {
// 			log.Fatalf("goose %v: %v", command, err)
// 		}
// 	}
// 	defer func() {
// 		if err := db.Close(); err != nil {
// 			log.Fatalf("goose: failed to close DB: %v\n", err)
// 		}
// 	}()
// }

type GooseRequest struct {
	Name     string `json:"name"`
	Command  string `json:"command"`
	Dbstring string `json:"dbstring"`
}

func main() {
	r := mux.NewRouter()
	r.HandleFunc("/goose", Migrate).Methods("POST")
	fmt.Println("started listening on port 8000")
	fmt.Println(http.ListenAndServe(":8000", r))
}

func gooseUp(w http.ResponseWriter, r *http.Request) {

	p := GooseRequest{}
	err := json.NewDecoder(r.Body).Decode(&p)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	dir := "."

	dbstring, command := p.Dbstring, p.Command
	// Connect to the database
	dbs, err := gorm.Open(postgres.Open(dbstring), &gorm.Config{})
	if err != nil {
		panic("failed to connect database")
	}
	fmt.Println("connected gorm to postgres")

	fmt.Println(command)

	sqlCommand := fmt.Sprintf("CREATE SCHEMA IF NOT EXISTS %s", p.Name)

	// Execute the raw SQL command
	result := dbs.Exec(sqlCommand)
	if result.Error != nil {
		w.WriteHeader(http.StatusBadRequest)
		panic("failed to execute raw SQL command")
	}

	fmt.Println("dbstring--", dbstring)

	db, err := goose.OpenDBWithDriver("postgres", dbstring+"?search_path="+p.Name)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		panic(err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			panic(err)
		}
	}()

	arguments := []string{}

	if err := goose.RunContext(context.Background(), command, db, dir, arguments...); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		panic(err)
	}

	w.WriteHeader(http.StatusOK)

}

func Migrate(w http.ResponseWriter, r *http.Request) {

	p := GooseRequest{}
	err := json.NewDecoder(r.Body).Decode(&p)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	dir := "."

	command := p.Command
	dbstring := p.Dbstring
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		fmt.Println("failed to connect database. error: %s", err)
		return
	}
	// Connect to the database
	db, err := goose.OpenDBWithDriver("postgres", dbstring)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		fmt.Println("failed to connect database. error: %s", err)
		return
	}
	fmt.Println("connected to postgres")

	sqlCommand := fmt.Sprintf("CREATE SCHEMA IF NOT EXISTS %s", p.Name)

	// Execute the raw SQL command
	_, err = db.Exec(sqlCommand)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		fmt.Println("failed to execute raw SQL command. error: %s", err.Error())
		return
	}

	query := fmt.Sprintf("SET SEARCH_PATH = %s;", p.Name)
	_, err = db.Exec(query)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		fmt.Println("error in connecting to database using goose. err: %s", err.Error())
		return
	}
	defer func() {
		if err := db.Close(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			fmt.Println("error in closing to goose db instance. err: %s", err.Error())
			return
		}
	}()

	if err := goose.RunContext(context.Background(), command, db, dir); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		fmt.Println("error in running goose migrations. err: %s", err.Error())
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Println("migration successful")
	return

}
