from langchain.prompts import PromptTemplate

def get_anime_prompt():
    with open("data/prompt_template.txt", "r") as file:
        template = file.read()

    return PromptTemplate(template=template, input_variables=["context", "question"])