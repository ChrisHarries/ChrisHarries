import random

def randomize_string(input_string):
    # Split the string into parts based on the dashes
    parts = input_string.split('-')
    
    # Combine all parts into a single list of characters
    char_list = list(''.join(parts))
    
    # Shuffle the characters
    random.shuffle(char_list)
    
    # Reconstruct the string with dashes in the original positions
    randomized_string = ''
    index = 0
    for part in parts:
        if index > 0:
            randomized_string += '-'
        randomized_string += ''.join(char_list[:len(part)])
        char_list = char_list[len(part):]
        index += 1
    
    return randomized_string

def generate_sql_updates(input_file, output_file):
    with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
        for line in infile:
            input_string = line.strip()
            if input_string:  # Ensure the line is not empty
                randomized_string = randomize_string(input_string)
                # Generate SQL update command
                sql_command = f"UPDATE \"b2b_membership\".\"B2BMemberships\" SET \"membershipId\" = '{randomized_string}' WHERE \"membershipId\" = '{input_string}';\n"
                outfile.write(sql_command)

if __name__ == "__main__":
    input_file = input("Enter the path to the input file: ")
    output_file = input("Enter the path to the output file: ")
    generate_sql_updates(input_file, output_file)
    print(f"SQL commands have been saved to {output_file}.")

